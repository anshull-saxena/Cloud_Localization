# PowerShell Scripts and Advanced Modules

The `scripts/` folder contains a modern, feature-rich refactoring of the localization pipeline. It introduces advanced optimizations for performance and monitoring.

## Core Scripts

- **`function1.ps1` (Extraction + Batching):**
    - Extends the basic extraction logic with **adaptive batching**.
    - Calculates token counts for each sentence to optimize batch sizes.
    - Generates SLA metrics at the start of the extraction run.
- **`function2.ps1` (Translation + Routing + SLA):**
    - Downloads XLIFF files and translates them using advanced routing logic.
    - Tracks per-sentence latency and model usage.
    - Generates a comprehensive SLA report at the end of the run.

## Utility Modules

- **`TokenUtils.ps1` (Token counting):**
    - Estimates token counts (using character-based or API-based methods).
    - Classifies sentences as "small" or "large" for routing decisions.
- **`BatchingUtils.ps1` (Adaptive batching):**
    - Creates batches of sentences that respect token budgets.
    - Logs batch statistics for research analysis.
- **`ModelRouter.ps1` (Hybrid NMT/LLM Routing):**
    - Decides whether to use NMT (Neural Machine Translation) or LLM (Large Language Models) based on sentence complexity.
    - Implements automatic fallback from LLM to NMT if the LLM fails.
- **`InfraRouter.ps1` (Infrastructure Routing):**
    - (Optional) Routes translation requests between a dedicated VM and Serverless functions based on concurrency and token load.
- **`SLALogger.ps1` (Performance Tracking):**
    - Tracks P50, P95, and P99 latency percentiles.
    - Detects SLA violations (e.g., if a run exceeds the deadline).
    - Generates detailed JSON reports in the `logs/` directory.

## Supporting Scripts

- **`analyze-optimal-threshold.ps1`:** Analyzes historical data to recommend the best token threshold for routing decisions.
- **`verify-azure-resources.ps1`:** Checks the status of required Azure resources (Blob Storage, SQL) before running the pipeline.
