# Python Scripts Reference

The Python scripts in this project are the core components of the localization pipeline. They are organized by phase and variant.

## Phase 1: `phase1.py`
**Description:** Extracts strings from `.resx` files and uploads them as XLIFF to Azure Blob Storage.

- **Main Functions:**
  - `extract_resx_to_xliff(resx_path, xliff_path)`: Parses `.resx` (XML) and generates `.xliff` (XML).
  - `upload_to_blob(file_path, container_name)`: Connects to Azure Blob Storage and uploads the file.
- **Workflow:**
  1.  Reads the source folder from `config.json`.
  2.  For each `.resx` file, it creates a corresponding XLIFF file.
  3.  Uploads XLIFF files to the `raw-files` container.

## Translation: `translation.py`
**Description:** Translates XLIFF files using a hybrid approach (SQL TM + Model).

- **Main Functions:**
  - `get_translation_from_db(source_text, target_lang)`: Queries the `Translations` table in Azure SQL.
  - `call_translation_model(source_text, target_lang)`:
    - In **API-based:** Calls Hugging Face Inference API.
    - In **VM-based:** Calls a FastAPI endpoint on a VM hosting mBART.
  - `translate_xliff(xliff_content, target_lang)`: Iterates through `<trans-unit>` elements in XLIFF and translates them.
- **Workflow:**
  1.  Downloads raw XLIFF from Azure Blob Storage.
  2.  Translates strings (TM first, then fallback to Model).
  3.  Updates the SQL TM table with new translations.
  4.  Uploads the translated XLIFF to the `trans-files` container.

## Phase 3: `phase3.py`
**Description:** Merges translated XLIFF files back into localized `.resx` files.

- **Main Functions:**
  - `merge_xliff_to_resx(xliff_path, original_resx_path, target_resx_path)`: Parses the translated XLIFF and the original `.resx` to create a new localized `.resx`.
  - `download_from_blob(container_name, blob_name)`: Downloads translated XLIFF files.
- **Workflow:**
  1.  Downloads translated XLIFF from Azure Blob Storage.
  2.  Reads the original `.resx` file to maintain its structure and metadata.
  3.  Inserts translated strings into the resource file.
  4.  Saves the final localized file to the target repository path.
