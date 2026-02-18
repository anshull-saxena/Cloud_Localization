# Project Overview: Cloud Localization Pipeline

This project is a robust, automated localization pipeline designed to translate `.resx` (Resource) files into multiple target languages. It leverages cloud infrastructure (Azure), machine learning models (Hugging Face / mBART), and a Translation Memory (SQL Database) to ensure efficient and consistent translations.

## Core Objective
To provide a scalable solution for localizing software applications by automating the extraction, translation, and merging of resource strings.

## Main Variants
The project offers two implementation paths for the translation phase:

1.  **API-Based (Hugging Face Inference API):**
    - Uses external Hugging Face APIs for translation.
    - Suitable for lightweight deployments and rapid prototyping.
    - Located in `API_based_HFace_AppInsight/`.

2.  **VM-Based (VM-hosted mBART):**
    - Uses a custom-hosted mBART model running on a Virtual Machine via FastAPI.
    - Suitable for high-volume translation tasks where data privacy or custom model tuning is required.
    - Located in `VM_MbartModel/`.

## Key Technologies
- **Python:** The core logic for extraction, translation, and merging is implemented in Python.
- **PowerShell:** A refactored version of the pipeline is available in PowerShell, offering advanced features like tokenization and adaptive batching.
- **Azure Blob Storage:** Used to store intermediate XLIFF files during the pipeline phases.
- **Azure SQL Database:** Acts as a **Translation Memory (TM)**, storing previous translations to avoid redundant model calls and ensure consistency.
- **Application Insights:** Integrated for monitoring, logging, and performance tracking (SLA metrics).
- **Hugging Face / mBART:** The underlying machine learning models used for Natural Language Processing (NLP).
