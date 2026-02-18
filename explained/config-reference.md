# `config.json` Configuration Reference

The `config.json` file controls the behavior of the localization pipeline. Below are the key parameters and their purposes.

## Core Settings
- `StorageAccountName`: The name of the Azure Blob Storage account.
- `ConnectionString`: Connection string for Azure Blob Storage.
- `TargetLanguages`: A list of language codes for translation (e.g., `["fr-FR", "es-ES", "hi-IN"]`).
- `SourceRepoPath`: The folder containing source `.resx` files (default: `source-folder`).
- `TargetRepoPath`: The folder where localized `.resx` files will be saved (default: `target-folder`).
- `SQLConnectionString`: Connection string for the Azure SQL Database (Translation Memory).

## Tokenization Settings
- `TokenizationMethod`: `"CharacterBased"` (approximates tokens as characters / 4) or `"APIBased"` (uses a real tokenizer API).
- `SmallSentenceThreshold`: The token count threshold that separates "small" (NMT-suitable) from "large" (LLM-suitable) sentences.

## Adaptive Batching
- `MaxTokenBatch`: Maximum number of tokens allowed per translation batch (default: 2000).
- `EnableAdaptiveBatching`: Enables grouping sentences into optimal token-aware batches.

## Model Routing (Disabled by Default)
- `EnableModelRouting`: Enables hybrid NMT/LLM routing.
- `NMTEndpoint`: Endpoint for the NMT service (e.g., Azure Translator).
- `LLMEndpoint`: Endpoint for the LLM service (e.g., GPT-4).
- `SmallSentenceModel`: The model type for small sentences (`"NMT"`).
- `LargeSentenceModel`: The model type for large sentences (`"LLM"`).

## Infrastructure Routing (Optional)
- `EnableInfraRouting`: Enables routing between VM and Serverless based on load.
- `ConcurrencyThreshold`: Number of concurrent requests before routing to a larger VM.
- `TokenLoadThreshold`: Total token count before routing to a larger VM.

## SLA Logging
- `EnableSLALogging`: Enables performance tracking and latency percentile calculation.
- `SLADeadlineSeconds`: Maximum allowed duration for a localization run (default: 3600s / 1 hour).
- `SLALogPath`: Path where SLA metrics are saved (default: `logs/sla-metrics.json`).
- `LogPerSentenceMetrics`: Enables detailed logging for every translated sentence.
