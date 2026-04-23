import json
import requests
import pyodbc
import os
import xml.etree.ElementTree as ET
import logging
import sys
import time
import asyncio
import statistics
import uuid
import psutil
import threading
from typing import List, Dict, Any

from azure.storage.blob import BlobServiceClient
try:
    from opencensus.ext.azure.log_exporter import AzureLogHandler
except ImportError:
    AzureLogHandler = None

# --- Configuration ---
BATCH_SIZE = 50

# --- Configure logging ---
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[logging.StreamHandler()]
)
logger = logging.getLogger(__name__)

# --- PerformanceProfiler (matching Gen2/Gen3) ---
class PerformanceProfiler:
    def __init__(self):
        self.process = psutil.Process(os.getpid())
        self.timings = {}
        self.reset_file_metrics()
        
    def reset_file_metrics(self):
        self.start_ts = time.perf_counter()
        self.counters = {
            "telemetry_overhead_ms": 0.0,
            "api_calls": 0,
            "cache_hits": 0,
            "cache_misses": 0,
            "sql_reads": 0,
            "sql_writes": 0,
            "tokens_processed": 0.0,
            "total_input_tokens": 0.0,
            "total_output_tokens": 0.0,
            "api_retries": 0,
            "api_failures": 0,
            "api_throttled": 0,
            "total_batches": 0,
            "total_chars_processed": 0,
            "total_segments": 0,
            "total_tm_hits": 0,
            "total_nmt_calls": 0,
            "nmt_latencies": [],
            "sleep_time_ms": 0.0
        }
    
    def start_timer(self, name):
        self.timings[name] = time.perf_counter()

    def stop_timer(self, name):
        if name in self.timings:
            return (time.perf_counter() - self.timings[name]) * 1000
        return 0

    def get_system_impact(self):
        return {
            "cpu_percent": self.process.cpu_percent(interval=None),
            "memory_mb": self.process.memory_info().rss / 1024 / 1024
        }
    
    def add_segment_stats(self, tm_hit=False, nmt_latency=None, is_nmt_only=False):
        self.counters["total_segments"] += 1
        if tm_hit:
            self.counters["total_tm_hits"] += 1
            self.counters["cache_hits"] += 1
        else:
            self.counters["cache_misses"] += 1
        if nmt_latency is not None:
            self.counters["total_nmt_calls"] += 1
            self.counters["nmt_latencies"].append(nmt_latency)

# Global profiler instance
profiler = PerformanceProfiler()

def load_config(config_path):
    with open(config_path, "r", encoding="utf-8") as f:
        return json.load(f)

def connect_sql(sql_conn_str):
    profiler.start_timer("sql_connect")
    conn = pyodbc.connect(sql_conn_str)
    profiler.stop_timer("sql_connect")
    return conn

def query_translation(cursor, source_text, target_lang):
    """Query translation with timing"""
    profiler.counters["sql_reads"] += 1
    profiler.start_timer("sql_read_latency")
    cursor.execute("SELECT TranslatedText FROM Translations WHERE SourceText=? AND TargetLang=?", (source_text, target_lang))
    row = cursor.fetchone()
    elapsed_ms = profiler.stop_timer("sql_read_latency")
    result = row[0] if row else None
    return result, elapsed_ms

def insert_translation(cursor, source_text, target_lang, translated_text):
    """Insert translation with timing"""
    profiler.counters["sql_writes"] += 1
    profiler.start_timer("sql_write_latency")
    cursor.execute("INSERT INTO Translations (SourceText, TargetLang, TranslatedText) VALUES (?, ?, ?)",
                   (source_text, target_lang, translated_text))
    elapsed_ms = profiler.stop_timer("sql_write_latency")
    return elapsed_ms

def translate_with_hf(texts, target_lang, hf_token, model_name="facebook/mbart-large-50-many-to-many-mmt"):
    """
    Translates a list of strings using Hugging Face Inference API.
    """
    if not texts:
        return [], 0

    profiler.counters["api_calls"] += 1
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
        return [None] * len(texts), 0

    tgt = lang_map[target_lang]

    profiler.start_timer("hf_network_latency")
    response = requests.post(
        API_URL,
        headers=headers,
        json={
            "inputs": texts,
            "parameters": {
                "src_lang": "en_XX",
                "tgt_lang": tgt
            }
        },
        timeout=60
    )
    latency_ms = profiler.stop_timer("hf_network_latency")

    if response.status_code != 200:
        logger.error(f"HF API error {response.status_code}: {response.text}")
        profiler.counters["api_failures"] += 1
        return [None] * len(texts), latency_ms

    result = response.json()
    
    # HF API returns a list of dicts for list input
    translations = []
    if isinstance(result, list):
        for item in result:
            if "translation_text" in item:
                translations.append(item["translation_text"])
            elif "generated_text" in item:
                translations.append(item["generated_text"])
            else:
                translations.append(None)
        return translations, latency_ms
    else:
        logger.error(f"Unexpected HF response format: {result}")
        return [None] * len(texts), latency_ms


async def translate_with_hf_async(texts, target_lang, hf_token, model_name="facebook/mbart-large-50-many-to-many-mmt"):
    return await asyncio.to_thread(translate_with_hf, texts, target_lang, hf_token, model_name)


async def process_xlf_file(xlf_path, target_lang, conn, hf_token, file_stats):
    """Process XLF file and return timing stats"""
    logger.info(f"🔄 Processing {xlf_path} for {target_lang}")
    
    profiler.start_timer("xml_parse")
    tree = ET.parse(xlf_path)
    root = tree.getroot()
    xml_parse_ms = profiler.stop_timer("xml_parse")

    cursor = conn.cursor()
    translated_count = 0
    skipped_count = 0
    total_source_chars = 0
    total_translated_chars = 0

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
        total_source_chars += len(source_text)
        cached, sql_time = query_translation(cursor, source_text, target_lang)
        file_stats["total_sql_time_ms"] += sql_time
        
        if cached:
            target_elem.text = cached
            total_translated_chars += len(cached)
            skipped_count += 1
            profiler.add_segment_stats(tm_hit=True)
        else:
            missing_indices.append(i)
            to_translate_texts.append(source_text)

    # 2. Batch Translation for missing
    total_hf_api_time_ms = 0.0
    
    for i in range(0, len(to_translate_texts), BATCH_SIZE):
        batch_texts = to_translate_texts[i : i + BATCH_SIZE]
        batch_indices = missing_indices[i : i + BATCH_SIZE]
        profiler.counters["total_batches"] += 1
        
        logger.info(f"🚀 Batch translating {len(batch_texts)} items...")
        translations, batch_latency_ms = await translate_with_hf_async(batch_texts, target_lang, hf_token)
        
        total_hf_api_time_ms += batch_latency_ms
        per_item_latency = batch_latency_ms / len(batch_texts) if batch_texts else 0

        for j, translated_text in enumerate(translations):
            if translated_text:
                original_idx = batch_indices[j]
                tu, source_text, target_elem = trans_units[original_idx]
                
                target_elem.text = translated_text
                total_translated_chars += len(translated_text)
                write_time = insert_translation(cursor, source_text, target_lang, translated_text)
                file_stats["total_sql_time_ms"] += write_time
                
                profiler.add_segment_stats(nmt_latency=per_item_latency)
                translated_count += 1
                
                # Token estimation
                input_tokens = len(source_text) / 4.0
                output_tokens = len(translated_text) / 4.0
                profiler.counters["total_input_tokens"] += input_tokens
                profiler.counters["total_output_tokens"] += output_tokens
                profiler.counters["tokens_processed"] += (input_tokens + output_tokens)
            else:
                skipped_count += 1

    profiler.start_timer("sql_commit")
    conn.commit()
    file_stats["total_commit_time_ms"] = profiler.stop_timer("sql_commit")
    
    file_stats["total_api_time_ms"] = total_hf_api_time_ms
    
    profiler.start_timer("xml_write")
    tree.write(xlf_path, encoding="utf-8", xml_declaration=True)
    xml_write_ms = profiler.stop_timer("xml_write")
    
    logger.info(f"✅ Completed {xlf_path}: {translated_count} new, {skipped_count} cached/skipped")
    
    return xml_parse_ms, xml_write_ms, total_source_chars, total_translated_chars

async def main(config_path):
    config = load_config(config_path)
    
    # Record cold start time
    cold_start_init = time.perf_counter()

    storage_conn_str = config["blob_connection_string"]
    raw_container = config["raw_container"]
    translated_container = config["translated_container"]
    sql_conn_str = config["sql_conn_str"]
    hf_token = config["hf_api_token"]
    
    # Read from environment variable first (for DevOps), then config
    app_insights_conn = os.getenv("APPINSIGHTS_CONNECTION_STRING") or config.get("app_insights_connection_string")

    # Configure App Insights logger
    ai_logger = None
    az_handler = None
    if AzureLogHandler and app_insights_conn and "InstrumentationKey" in app_insights_conn:
        try:
            ai_logger = logging.getLogger("app_insights_logger")
            az_handler = AzureLogHandler(connection_string=app_insights_conn)
            if not hasattr(az_handler, 'lock') or az_handler.lock is None:
                az_handler.lock = threading.RLock()
            ai_logger.addHandler(az_handler)
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
    
    cold_start_ms = (time.perf_counter() - cold_start_init) * 1000

    for blob in raw_client.list_blobs():
        # Reset profiler for each file
        profiler.reset_file_metrics()
        file_start = time.perf_counter()
        
        blob_name = blob.name
        local_path = os.path.basename(blob_name)
        
        # Track blob download
        profiler.start_timer("blob_download")
        with open(local_path, "wb") as f:
            f.write(raw_client.get_blob_client(blob).download_blob().readall())
        download_ms = profiler.stop_timer("blob_download")

        parts = blob_name.split(".")
        if len(parts) < 2:
            logger.warning(f"⚠️ Skipping blob {blob_name}, unexpected name format")
            continue
        target_lang = parts[-2]  # e.g. MyFile.resx.fr-FR.xlf → "fr-FR"

        logger.info(f"🌍 Translating {blob_name} → {target_lang}")
        
        # Initialize file_stats
        file_stats = {"total_api_time_ms": 0, "total_sql_time_ms": 0, "total_commit_time_ms": 0}
        
        xml_parse_ms, xml_write_ms, total_source_chars, total_translated_chars = await process_xlf_file(
            local_path, target_lang, conn, hf_token, file_stats
        )

        # Track blob upload
        profiler.start_timer("blob_upload")
        trans_client.upload_blob(name=blob_name, data=open(local_path, "rb"), overwrite=True)
        upload_ms = profiler.stop_timer("blob_upload")
        
        raw_client.delete_blob(blob_name)
        os.remove(local_path)
        logger.info(f"📤 Uploaded translated {blob_name} and removed from raw container")
        
        # Calculate metrics (matching Gen2/Gen3 format)
        file_duration = (time.perf_counter() - file_start) * 1000
        
        total_segments = profiler.counters["total_segments"]
        total_tm_hits = profiler.counters["total_tm_hits"]
        total_nmt_calls = profiler.counters["total_nmt_calls"]
        nmt_latencies = profiler.counters["nmt_latencies"]
        
        avg_nmt_latency = statistics.mean(nmt_latencies) if nmt_latencies else 0.0
        elapsed_s = max(1, file_duration / 1000)
        throughput_seg_hr = int((total_segments / elapsed_s) * 3600) if total_segments > 0 else 0
        
        total_tokens = profiler.counters["tokens_processed"]
        total_input_t = profiler.counters["total_input_tokens"]
        total_output_t = profiler.counters["total_output_tokens"]
        batches = max(1, profiler.counters["total_batches"])
        
        avg_segment_len = total_source_chars / max(1, total_segments)
        char_token_ratio = round(total_source_chars / max(1, total_tokens), 2)
        avg_batch_size = round(total_tokens / batches, 2)
        ms_per_token = round(file_stats["total_api_time_ms"] / max(1, total_tokens), 4)
        
        sleep_time_ms = profiler.counters.get("sleep_time_ms", 0.0)
        hf_time = file_stats["total_api_time_ms"]
        total_network_wait_ms = hf_time + file_stats["total_sql_time_ms"] + file_stats["total_commit_time_ms"] + download_ms + upload_ms
        compute_time_ms = max(0, file_duration - total_network_wait_ms - sleep_time_ms)
        io_bound_ratio = round((total_network_wait_ms / max(1, file_duration)) * 100, 2)
        
        sys_stats = profiler.get_system_impact()
        
        # Build metrics_payload (MATCHING Gen2/Gen3 FORMAT)
        metrics_payload = {
            "run_invocation_id": str(uuid.uuid4()),
            "file_name": blob_name,
            "target_lang": target_lang,
            "throughput_seg_per_hr": throughput_seg_hr,
            "throughput_input_tokens_per_hr": round((total_input_t / elapsed_s) * 3600, 2),
            "total_api_call_logically": profiler.counters["total_batches"],
            "actual_api_call": profiler.counters["api_calls"],
            "total_segments": total_segments,
            "avg_segment_char_length": avg_segment_len,
            "text_expansion_ratio": round(total_translated_chars / max(1, total_source_chars), 2),
            "tokens_processed_in_whole_language": total_tokens,
            "total_input_tokens_source": round(total_input_t, 2),
            "total_output_tokens_target": round(total_output_t, 2),
            "avg_input_tokens_per_batch": round(total_input_t / batches, 2),
            "avg_output_tokens_per_batch": round(total_output_t / batches, 2),
            "char_per_token_ratio": char_token_ratio,
            "total_token_input_plus_output_per_batch": avg_batch_size,
            "time_per_token": ms_per_token,
            "nmt_calls": total_nmt_calls,
            "transational_memory_hits": total_tm_hits,
            "cache_rate": (profiler.counters["cache_hits"] / max(1, profiler.counters["cache_hits"] + profiler.counters["cache_misses"])) * 100,
            "total_time": file_duration,
            "cold_start_init_ms": cold_start_ms,
            "compute_time_ms": compute_time_ms,
            "total_sleep_time_ms": sleep_time_ms,
            "network_wait_time_ms": total_network_wait_ms,
            "io_bound_pipeline_pct": io_bound_ratio,
            "hf_api_wait_ms": hf_time,
            "azure_sql_query_ms": file_stats["total_sql_time_ms"],
            "azure_sql_commit_ms": file_stats["total_commit_time_ms"],
            "xml_parse_ms": xml_parse_ms,
            "xml_disk_write_ms": xml_write_ms,
            "blob_download_ms": download_ms,
            "blob_upload_ms": upload_ms,
            "telemetry_overhead_ms": profiler.counters["telemetry_overhead_ms"],
            "cpu_usage_pct": sys_stats['cpu_percent'],
            "memory_mb": sys_stats['memory_mb'],
            "serverless_cost_gb_sec": round((sys_stats['memory_mb'] / 1024) * (file_duration / 1000), 4),
            "api_retries": profiler.counters["api_retries"],
            "api_failures": profiler.counters["api_failures"],
            "api_throttled_429": profiler.counters.get("api_throttled", 0)
        }
        
        # Log in RESEARCH_DATA format (matching Gen2/Gen3)
        logger.info(f"📊 RESEARCH_DATA: {json.dumps(metrics_payload)}")
        
        # Send to App Insights
        if ai_logger:
            ai_logger.info(f"📊 RESEARCH_DATA: {json.dumps(metrics_payload)}")
            if az_handler:
                try:
                    az_handler.flush()
                except Exception:
                    pass
            logger.info(f"📡 Sent metrics to App Insights for {blob_name}")

    conn.close()
    logger.info("🎉 Phase2 translation completed successfully")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python translation.py <config.json>")
        sys.exit(1)
    asyncio.run(main(sys.argv[1]))
