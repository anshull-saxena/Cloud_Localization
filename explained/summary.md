# Localization Project Summary

This project provides a comprehensive and scalable solution for automating the localization of `.resx` files. By combining established localization standards (XLIFF), modern machine learning (Hugging Face / mBART), and cloud-native monitoring (Azure Application Insights), it ensures high-quality, cost-effective translations.

## Quick Links
- [Project Overview](project-overview.md): What this project is and why it exists.
- [Pipeline Architecture](pipeline-architecture.md): Understanding the 3-phase (Extract, Translate, Merge) process.
- [Python Scripts](scripts-python.md): Deep dive into the core Python logic.
- [PowerShell Scripts](scripts-powershell.md): Exploring advanced features like adaptive batching and SLA logging.
- [Configuration Reference](config-reference.md): How to customize the pipeline via `config.json`.
- [Infrastructure and Services](infrastructure.md): Details on the cloud services and ML models used.

## Conclusion
Whether using the straightforward **API-based** variant or the more performant **VM-based** and **PowerShell-refactored** versions, this project is designed to handle localization at scale while maintaining a high level of observability and performance tracking.
