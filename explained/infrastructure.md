# Infrastructure and Services

The project relies on a distributed architecture using Azure cloud services and external Machine Learning models.

## Azure Blob Storage
**Purpose:** Acts as the data interchange layer between different phases of the pipeline.
- **`raw-files` container:** Stores the initial XLIFF files extracted from `.resx`.
- **`trans-files` container:** Stores the translated XLIFF files.
- **Persistence:** Allows for asynchronous processing where one phase can finish, and the next can pick up the work later.

## Azure SQL Database (Translation Memory)
**Purpose:** Stores and retrieves previous translations to improve efficiency and consistency.
- **Table:** `Translations`
- **Columns:**
    - `SourceText`: The original string.
    - `TargetLang`: The target language code.
    - `TranslatedText`: The stored translation.
- **Benefits:**
    - **Cost Reduction:** Avoids expensive model calls for already-translated strings.
    - **Consistency:** Ensures the same string is always translated the same way across the application.

## Application Insights (Monitoring)
**Purpose:** Provides observability and telemetry for the localization process.
- **SLA Metrics:** Logs P50, P95, and P99 latencies to monitor the speed of the translation model.
- **Success Tracking:** Logs successful and failed translation attempts.
- **Queries:** `ApplicationInsights-Queries.md` contains sample KQL (Kusto Query Language) queries to analyze the performance data.

## Machine Learning Models
- **Hugging Face (Inference API):** Used in the API-based variant for external translation calls.
- **mBART (Hugging Face):** A multilingual Sequence-to-Sequence (Seq2Seq) model specifically designed for translation tasks. It is hosted on a VM in the VM-based variant.
- **GPT-4 (LLM):** Optional model used via `ModelRouter.ps1` for high-complexity sentences.

## CI/CD (Azure DevOps)
- **`azure-pipelines.yml`:** Automates the execution of Phase 1, 2, and 3 in the cloud. It manages environment variables, dependencies, and repo commits.
