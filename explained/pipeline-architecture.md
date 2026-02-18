# Pipeline Architecture: The 3-Phase Process

The localization pipeline is structured into three distinct phases to ensure separation of concerns and scalability. Each phase can be run independently or as part of a continuous integration (CI) pipeline.

## Phase 1: Extraction (`phase1.py` / `function1.ps1`)
**Goal:** Extract translatable strings from `.resx` files and prepare them for translation.

1.  **Read Resource Files:** Scans the `source-folder/` for `.resx` files.
2.  **XLIFF Generation:** Converts the `.resx` XML format into **XLIFF (XML Localization Interchange File Format)**, which is the industry standard for localization tools.
3.  **Adaptive Batching (PowerShell version):** Uses `BatchingUtils.ps1` and `TokenUtils.ps1` to group strings into optimal batches based on token budgets.
4.  **Upload to Azure Blob Storage:** Stores the generated XLIFF files in the `raw-files` (or `xliff-temp-files`) container for the next phase.

---

## Phase 2: Translation (`translation.py` / `function2.ps1`)
**Goal:** Translate the extracted strings using a combination of Translation Memory and Machine Learning models.

1.  **Download XLIFF:** Retrieves raw XLIFF files from Azure Blob Storage.
2.  **Check Translation Memory (SQL):** Queries an Azure SQL database to see if a translation already exists for the given source text and target language.
3.  **Machine Translation (Fallback):** If no translation is found in the TM, the script calls either:
    -   **Hugging Face Inference API** (API-based variant)
    -   **mBART via FastAPI** (VM-based variant)
    -   **NMT or LLM** (PowerShell version with `ModelRouter.ps1`)
4.  **Update Translation Memory:** Stores newly translated strings back into the SQL database.
5.  **Upload Translated XLIFF:** Stores the translated XLIFF files in the `trans-files` container.

---

## Phase 3: Merging (`phase3.py` / `function2.ps1` completion)
**Goal:** Integrate the translated strings back into the application's resource files.

1.  **Download Translated XLIFF:** Retrieves translated files from Azure Blob Storage.
2.  **Merge into .resx:** Combines the translated strings from XLIFF back into the `.resx` format.
3.  **Local Save:** Saves the localized `.resx` files (e.g., `resx_file_01_fr-FR.resx`) into the `target-folder/`.
4.  **Finalize:** Completes any final logging or reporting (SLA reports).
