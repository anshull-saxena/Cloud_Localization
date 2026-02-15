import json
import requests
import pyodbc
import os
import xml.etree.ElementTree as ET
import logging

import sys, time, statistics
from typing import List, Dict, Any

from azure.storage.blob import BlobServiceClient
try:
    from opencensus.ext.azure.log_exporter import AzureLogHandler
except ImportError:
    AzureLogHandler = None

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[logging.StreamHandler()]
)
logger = logging.getLogger(__name__)

def load_config(config_path):
    with open(config_path, "r", encoding="utf-8") as f:
        return json.load(f)

def connect_sql(sql_conn_str):
    return pyodbc.connect(sql_conn_str)

def query_translation(cursor, source_text, target_lang):
    cursor.execute("SELECT TranslatedText FROM Translations WHERE SourceText=? AND TargetLang=?", (source_text, target_lang))
    row = cursor.fetchone()
    return row[0] if row else None

def insert_translation(cursor, source_text, target_lang, translated_text):
    cursor.execute("INSERT INTO Translations (SourceText, TargetLang, TranslatedText) VALUES (?, ?, ?)",
                   (source_text, target_lang, translated_text))

def translate_with_hf(texts, target_lang, hf_token, model_name="facebook/mbart-large-50-many-to-many-mmt"):
    """
    Translates a list of strings using Hugging Face Inference API.
    """
    if not texts:
        return []

    headers = {"Authorization": f"Bearer {hf_token}"}
    API_URL = f"https://router.huggingface.co/hf-inference/models/{model_name}"

    # Extended mapping from BCP-47 to mBART-50 tokens
    lang_map = {
        "ar-SA": "ar_AR",
        "de-DE": "de_DE",
        "en-US": "en_XX",
        "es-ES": "es_XX",
        "fr-FR": "fr_XX",
        "hi-IN": "hi_IN",
        "it-IT": "it_IT",
        "ja-JP": "ja_XX",
        "ko-KR": "ko_KR",
        "nl-NL": "nl_XX",
        "pl-PL": "pl_PL",
        "pt-PT": "pt_XX",
        "pt-BR": "pt_BR",
        "ru-RU": "ru_RU",
        "sv-SE": "sv_SE",
        "tr-TR": "tr_TR",
        "uk-UA": "uk_UA",
        "zh-CN": "zh_CN",
        "zh-TW": "zh_TW",
    }

    if target_lang not in lang_map:
        logger.warning(f"⚠️ Skipping translation: language {target_lang} not supported in lang_map")
        return [None] * len(texts)

    tgt = lang_map[target_lang]

    response = requests.post(
        API_URL,
        headers=headers,
        json={
            "inputs": texts,
            "parameters": {
                "src_lang": "en_XX",   # all your source resx files are English
                "tgt_lang": tgt
            }
        }
    )

    if response.status_code != 200:
        logger.error(f"HF API error {response.status_code}: {response.text}")
        return [None] * len(texts)

    result = response.json()
    
    # HF API returns a list of dicts for list input
    # [{"translation_text": "foo"}, {"translation_text": "bar"}]
    translations = []
    if isinstance(result, list):
        for item in result:
            if "translation_text" in item:
                translations.append(item["translation_text"])
            elif "generated_text" in item:
                translations.append(item["generated_text"])
            else:
                translations.append(None)
        return translations
    else:
        logger.error(f"Unexpected HF response format: {result}")
        return [None] * len(texts)


# ---------------- Metrics ----------------
class RunMetrics:
    def __init__(self):
        self.start_ts = time.perf_counter()
        self.total_segments = 0
        self.total_tm_hits = 0
        self.total_nmt_calls = 0
        self.nmt_latencies: List[float] = []

    def add_segment(self, tm_hit=False, nmt_latency=None):
        self.total_segments += 1
        if tm_hit:
            self.total_tm_hits += 1
        if nmt_latency is not None:
            self.total_nmt_calls += 1
            self.nmt_latencies.append(nmt_latency)

    def summary(self):
        elapsed = time.perf_counter() - self.start_ts
        avg_nmt = statistics.mean(self.nmt_latencies) if self.nmt_latencies else 0.0
        throughput = (self.total_segments / elapsed) * 3600 if elapsed > 0 else 0.0
        return {
            "total_files": 1,
            "total_segments": self.total_segments,
            "total_tm_hits": self.total_tm_hits,
            "total_nmt_calls": self.total_nmt_calls,
            "total_time_sec": round(elapsed, 2),
            "avg_nmt_latency_sec": round(avg_nmt, 4),
            "overall_throughput_seg_per_hr": int(throughput)
        }




def process_xlf_file(xlf_path, target_lang, conn, hf_token, metrics):
    logger.info(f"🔄 Processing {xlf_path} for {target_lang}")
    tree = ET.parse(xlf_path)
    root = tree.getroot()

    cursor = conn.cursor()
    translated_count = 0
    skipped_count = 0

    # Collect all units first
    trans_units = []
    for tu in root.findall(".//trans-unit"):
        source_elem = tu.find("source")
        target_elem = tu.find("target")
        if source_elem is None or target_elem is None:
            continue
        source_text = source_elem.text or ""
        if not source_text.strip():
            continue
        trans_units.append((tu, source_text, target_elem))

    # 1. Check SQL cache for all
    missing_indices = []
    to_translate_texts = []
    
    for i, (tu, source_text, target_elem) in enumerate(trans_units):
        cached = query_translation(cursor, source_text, target_lang)
        if cached:
            target_elem.text = cached
            skipped_count += 1
            metrics.add_segment(tm_hit=True)
        else:
            missing_indices.append(i)
            to_translate_texts.append(source_text)

    # 2. Batch Translation for missing
    BATCH_SIZE = 50
    for i in range(0, len(to_translate_texts), BATCH_SIZE):
        batch_texts = to_translate_texts[i : i + BATCH_SIZE]
        batch_indices = missing_indices[i : i + BATCH_SIZE]
        
        t0 = time.perf_counter()
        
        logger.info(f"🚀 Batch translating {len(batch_texts)} items...")
        translations = translate_with_hf(batch_texts, target_lang, hf_token)
        
        latency = time.perf_counter() - t0
        # Amortize latency per item for metrics (approx)
        per_item_latency = latency / len(batch_texts) if batch_texts else 0

        for j, translated_text in enumerate(translations):
            if translated_text:
                original_idx = batch_indices[j]
                tu, source_text, target_elem = trans_units[original_idx]
                
                target_elem.text = translated_text
                insert_translation(cursor, source_text, target_lang, translated_text)
                
                metrics.add_segment(nmt_latency=per_item_latency)
                translated_count += 1
            else:
                skipped_count += 1

    conn.commit()
    tree.write(xlf_path, encoding="utf-8", xml_declaration=True)
    logger.info(f"✅ Completed {xlf_path}: {translated_count} new, {skipped_count} cached/skipped")

def main(config_path):
    config = load_config(config_path)


    # Metrics tracker for this file
    metrics = RunMetrics()

    storage_conn_str = config["blob_connection_string"]
    raw_container = config["raw_container"]
    translated_container = config["translated_container"]
    sql_conn_str = config["sql_conn_str"]
    hf_token = config["hf_api_token"]
    app_insights_conn = config.get("app_insights_connection_string")

    # Configure App Insights logger
    ai_logger = None
    if AzureLogHandler and app_insights_conn and "InstrumentationKey" in app_insights_conn:
        try:
            ai_logger = logging.getLogger("app_insights_logger")
            ai_logger.addHandler(AzureLogHandler(connection_string=app_insights_conn))
            ai_logger.setLevel(logging.INFO)
            logger.info("✅ Azure Application Insights configured")
        except Exception as e:
            logger.warning(f"⚠️ Failed to configure App Insights: {e}")

    blob_service = BlobServiceClient.from_connection_string(storage_conn_str)
    raw_client = blob_service.get_container_client(raw_container)
    trans_client = blob_service.get_container_client(translated_container)
    if not trans_client.exists():
        trans_client.create_container()

    conn = connect_sql(sql_conn_str)

    for blob in raw_client.list_blobs():
        blob_name = blob.name
        local_path = os.path.basename(blob_name)
        with open(local_path, "wb") as f:
            f.write(raw_client.get_blob_client(blob).download_blob().readall())

        parts = blob_name.split(".")
        if len(parts) < 2:
            logger.warning(f"⚠️ Skipping blob {blob_name}, unexpected name format")
            continue
        target_lang = parts[-2]  # e.g. MyFile.resx.fr-FR.xlf → "fr-FR"

        logger.info(f"🌍 Translating {blob_name} → {target_lang}")
        process_xlf_file(local_path, target_lang, conn, hf_token, metrics)

        # Upload translated
        trans_client.upload_blob(name=blob_name, data=open(local_path, "rb"), overwrite=True)
        raw_client.delete_blob(blob_name)
        os.remove(local_path)
        logger.info(f"📤 Uploaded translated {blob_name} and removed from raw container")
        # 🔑 Print metrics summary for this file 
        summary = metrics.summary()
        logger.info("METRICS SUMMARY: %s", json.dumps(summary, ensure_ascii=False))

        # Send to App Insights
        if ai_logger:
            properties = {
                "File": blob_name,
                "Lang": target_lang,
                "Segments": summary["total_segments"],
                "TMHits": summary["total_tm_hits"],
                "NMTCalls": summary["total_nmt_calls"],
                "AvgLatency": summary["avg_nmt_latency_sec"],
                "TotalTime": summary["total_time_sec"]
            }
            ai_logger.info("TranslationMetrics", extra={"custom_dimensions": properties})
            logger.info(f"📡 Sent metrics to App Insights for {blob_name}")

    conn.close()

    logger.info("🎉 Phase2 translation completed successfully")

if __name__ == "__main__":
    import sys
    if len(sys.argv) != 2:
        print("Usage: python translation.py <config.json>")
        sys.exit(1)
    main(sys.argv[1])
