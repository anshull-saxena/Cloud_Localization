# High-Level Design (HLD): CR-Batch Cloud Localization Engine

## 1. System Architecture
![System Architecture](assets/hld_system_architecture.jpg)

## 2. Algorithmic Core Micro-Architecture
![CR-Batch Core Pipeline](assets/hld_cr_batch_core.jpg)

## 3. End-to-End Sequence Flow
![Sequence Flow](assets/hld_sequence_flow.jpg)

## 4. Algorithmic Pillars
1. **Radix-Trie Prefix Hashing:** Groups leading syntax tokens modulo 16 to maximize cache locality and minimize beam divergence.
2. **Conformal Quantile Risk Control (tau=0.90):** Calibrates finite-sample target length upper-bounds to eliminate autoregressive decoder tail stragglers.
3. **1D Monge Optimal Transport Sorting:** Sorts along scalar coordinate $Z_i = (L_{safe} \times 100) + Bucket_{ID}$, achieving provably minimal padding waste in $O(N \log N)$ time.
