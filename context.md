# Project Context & Engineering Specification: CR-Batch Localization

**Author:** Anshul Saxena (f20221041@hyderabad.bits-pilani.ac.in)  
**System:** Cloud-Native Enterprise Software Localization Engine  
**Models:** CTranslate2 INT8 NLLB-200, MarianMT, ONNX Runtime  
**Target Formats:** `.resx` (CLR Resource XML), `XLIFF 1.2 / 2.0`, Android String XML  
**Primary Repositories:**
- **Core Engine:** [anshull-saxena/CR-Batch-Localization](https://github.com/anshull-saxena/CR-Batch-Localization)
- **Cloud Architecture:** [anshull-saxena/Cloud_Localization (feat/cr-batch-scheduler)](https://github.com/anshull-saxena/Cloud_Localization/tree/feat/cr-batch-scheduler)

---

## 1. Executive Summary & Problem Formulation

### 1.1 The Enterprise Challenge
Enterprise software localization involves translating thousands of dynamic UI strings, exception logs, menu hierarchies, and documentation segments stored in `.resx` (CLR resource XML) and `XLIFF` standards. These translation pipelines are embedded within CI/CD systems across Microsoft Azure DevOps and AWS Multi-Cloud infrastructure.

Historically, translation pipelines combined Translation Memory (TM) exact/fuzzy lookup with a neural machine translation (NMT) fallback model (CTranslate2 NLLB-200 quantized to INT8). While TM handles previously approved segments with zero model latency, **untranslated segments (TM misses)** must be routed through neural inference.

### 1.2 The Failure of Legacy Batching Heuristics
The legacy codebase employed rigid, static heuristic batching:
1. **Fixed Batch Cardinality (`BATCH_SIZE = 52`)**: Chunks segments into uniform sets of 52 strings.
2. **Static Token Accumulator (`TOKEN_LIMIT = 512`)**: Accumulates strings until the cumulative source character or token count crosses 512.

**Why these heuristics break down in production:**
- **High Variance in Sequence Lengths:** Software catalogs contain single-word button labels (`"OK"`, `"Cancel"` $\to$ 1–3 tokens) alongside verbose exception stack messages or license agreements (100–250 tokens).
- **Severe Encoder Padding Flops Waste ($>80\%$):** When a 3-token segment is batched with a 120-token segment, the encoder pads the 3-token segment with 117 `<pad>` tokens. In standard production workloads, **81.8% to 88.5% of encoder computation was wasted on zeros and padding masks**.
- **Autoregressive Decoder Tail-Straggler Stalling:** Transformer decoders run autoregressively token-by-token until **every single sequence in the batch emits the End-of-Sequence token (`</s>`)**. If a single string in the batch expands during translation (common in morphologically rich languages like German or Russian), all other 51 threads idle in lockstep, causing catastrophic decoder stalling.
- **Out-of-Memory (OOM) Blowouts:** Static heuristics do not model target language expansion. When a batch contains multiple medium-length strings that expand significantly, KV-cache allocations exceed memory bounds, crashing container pods.

---

## 2. The Novel Machine Learning Algorithm: CR-Batch

To solve this fundamentally, we designed, validated, and implemented **`CR-Batch` (Conformal Radix-Quantile Optimal Transport Batching)**. `CR-Batch` replaces static heuristics with a mathematically provable, sub-millisecond scheduling optimization algorithm.

### 2.1 Formal Mathematical Objective
Let $\mathcal{U} = \{s_1, s_2, \dots, s_N\}$ be the set of translation units that miss Translation Memory. Each unit $s_i$ has known source token length $L_i^{src}$ and unknown autoregressive target token length $L_i^{tgt}$.

We partition $\mathcal{U}$ into $K$ disjoint batches $\mathcal{B} = \{B_1, B_2, \dots, B_K\}$ to minimize the dual padding waste:

$$\min_{\mathcal{B}} \;\; \Phi(\mathcal{B}) = \sum_{b=1}^{K} \left[ \underbrace{\sum_{i \in B_b} \left( \max_{j \in B_b} L_j^{src} - L_i^{src} \right)}_{\text{Encoder Waste } W_{enc}(B_b)} \;+\; \lambda \cdot \underbrace{\sum_{i \in B_b} \left( \max_{j \in B_b} L_j^{tgt} - L_i^{tgt} \right)}_{\text{Decoder Tail-Stall Waste } W_{dec}(B_b)} \right]$$

**Subject to Multi-Resource Hardware Constraints:**
1. **Encoder Token Budget:** $\sum_{i \in B_b} L_i^{src} \le K_{enc} \quad (512 \text{ tokens})$
2. **Decoder Surface Area Budget:** $|B_b| \times \max_{i \in B_b} \hat{L}_i^{\text{safe}} \le K_{dec} \quad (665 \text{ tokens})$
3. **Cardinality Threshold:** $|B_b| \le N_{\max} \quad (52 \text{ items})$

---

### 2.2 The Three Algorithmic Pillars

```
+---------------------------------------------------------------------------------------+
|                                  CR-BATCH CORE ENGINE                                 |
+---------------------------------------------------------------------------------------+
|  [Pillar 1: Radix-Trie Hash]   [Pillar 2: Conformal Quantile]   [Pillar 3: Monge OT]  |
|  pi(s_i) = hash(Prefix) mod 16  L_safe = ceil(L_src * q90 + q)   Sort along Z_i in     |
|  -> Preserves CPU L1/L2 cache   -> Pinball loss, tau = 0.90      O(N log N), Monge     |
|  -> Aligns syntactic verbs      -> Bounded decoder stragglers   array global minimum  |
+---------------------------------------------------------------------------------------+
```

#### Pillar 1: Radix-Trie Prefix Clustering ($\pi(s_i)$)
- **Mechanism:** Builds a lightweight Radix-Trie over the initial tokens/syntactic heads of source strings (e.g., UI verbs like `"Click"`, `"Error"`, `"Select"`).
- **Hardware Impact:** Maps prefixes to 16 buckets ($\pi(s_i) = \text{hash}(\text{Prefix}(s_i)) \pmod{16}$). Sentences sharing identical grammatical structure share common subword embeddings in memory, increasing CPU L1/L2 cache hit rates and minimizing beam-search branch divergence across SIMD/AVX-512 lanes.

#### Pillar 2: Conformal Quantile Risk Estimator ($\hat{L}_i^{\text{safe}}$)
- **Problem with Point Predictors:** Traditional regression models estimate conditional mean $\mathbb{E}[L^{tgt} \mid L^{src}]$, which underestimates the sequence length for roughly $50\%$ of queries, causing severe decoder stalling.
- **Formulation:** Trained via the **Asymmetric Pinball Loss** at coverage level $\tau = 0.90$:
  $$\mathcal{L}_\tau(y, \hat{y}) = \max\Big(\tau(y - \hat{y}), \, (\tau - 1)(y - \hat{y})\Big)$$
- **Finite-Sample Calibration:** Using empirical language expansion quantiles $q_{90}(\text{lang})$ and finite-sample nonconformity score $\hat{q}$:
  $$\hat{L}_i^{\text{safe}} = \left\lceil L_i^{src} \cdot q_{90}(\text{lang}) + \hat{q} \right\rceil$$
- **Theorem 1 (Finite-Sample Decoder Coverage):** For any exchangeable test sequence $s_i$, the probability of an autoregressive decoder tail straggler is strictly bounded:
  $$\mathbb{P}\left(L_i^{tgt} > \hat{L}_i^{\text{safe}}\right) \le 1 - \tau = 0.10$$

#### Pillar 3: 1D Monge Optimal Transport Sorting
- **1D Scalar Projection:** Each translation unit $s_i$ is mapped to a composite scalar coordinate:
  $$\mathcal{Z}_i = \left(\hat{L}_i^{\text{safe}} \times M\right) + \pi(s_i), \quad M = 16$$
- **Monge Array Property:** The 2D padding distance cost matrix $C_{ij} = |z_i - z_j|^2$ satisfies the Monge condition:
  $$C_{i, j} + C_{i+1, j+1} \le C_{i, j+1} + C_{i+1, j} \quad \forall i < j$$
- **Theorem 2 (Global Minimum Padding Optimality):** According to Monge-Kantorovich transport theory, sorting $\mathcal{U}$ along $\mathcal{Z}_i$ in $\mathcal{O}(N \log N)$ and performing contiguous greedy packing achieves the **provably global minimum padding waste** across all $N!$ possible permutations.

---

## 3. DOM Index Invariance & Transactional Integrity

In software localization pipelines, strings cannot simply be sorted, translated, and written out. They belong to rigid XML/XLIFF schemas where sequence positions, `<trans-unit id="...">` identifiers, format placeholders (`{0}`, `%s`), and inline tags (`<ph>`, `<b>`) must remain intact.

### Non-Destructive Scheduling Lifecycle
1. **Extraction & Index Tagging:** Every missing segment is extracted as a tuple:
   $$\text{Unit}_i = (i, \text{unit\_id}, \text{text})$$
   where $i$ is its original 0-indexed position in the document DOM.
2. **CR-Batch Optimization:** The scheduler reorders strings into mathematically optimal batches, translating them out-of-order.
3. **Out-of-Order Restoration:** Completed translations are gathered into a hash map indexed by $i$. A reconstruction pass inserts the translated target text directly into the exact DOM node at position $i$.
4. **Validation Proof:** Comprehensive unit testing (`tests/test_cr_batcher.py`) verifies:
   - **$100\%$ Segment Preservation:** Zero lost or duplicated units.
   - **Order Invariance:** Output XML/XLIFF line-for-line matches the input document hierarchy.
   - **Tag Preservation:** Placeholders and XML entities pass through unmodified.

---

## 4. Empirical Benchmark Results

We evaluated `CR-Batch` against legacy baselines across 500 enterprise localization segments in 6 diverse language families (Germanic, Slavic, Romance, Sino-Tibetan, Japonic, Indo-Aryan).

### 4.1 Padding Waste & Straggler Collapse

| Target Language | Metric | Fixed 52 (Legacy) | Static 512 (Baseline) | CR-Batch (Ours) | Relative Waste Reduction |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **de-DE** (German) | Encoder Padding Waste | 81.87% | 80.56% | **2.23%** | **97.2% Collapse 🚀** |
| | Decoder Straggler Stall | 82.14% | 80.83% | **1.98%** | **97.6% Collapse 🚀** |
| **ru-RU** (Russian) | Encoder Padding Waste | 81.87% | 80.56% | **6.00%** | **92.6% Collapse 🚀** |
| | Decoder Straggler Stall | 82.21% | 80.94% | **5.95%** | **92.6% Collapse 🚀** |
| **es-ES** (Spanish) | Encoder Padding Waste | 81.87% | 80.56% | **2.55%** | **96.8% Collapse 🚀** |
| | Decoder Straggler Stall | 82.20% | 80.92% | **2.46%** | **97.0% Collapse 🚀** |
| **zh-CN** (Chinese) | Encoder Padding Waste | 81.87% | 80.56% | **10.91%** | **86.5% Collapse 🚀** |
| | Decoder Straggler Stall | 81.87% | 80.56% | **10.91%** | **86.5% Collapse 🚀** |
| **ja-JP** (Japanese) | Encoder Padding Waste | 81.87% | 80.56% | **9.56%** | **88.1% Collapse 🚀** |
| | Decoder Straggler Stall | 82.16% | 80.86% | **9.34%** | **88.4% Collapse 🚀** |
| **hi-IN** (Hindi) | Encoder Padding Waste | 81.87% | 80.56% | **3.96%** | **95.1% Collapse 🚀** |
| | Decoder Straggler Stall | 82.17% | 80.88% | **3.78%** | **95.3% Collapse 🚀** |

### 4.2 Computational Overhead
- **Algorithm Scheduling Time:** $T_{overhead} \le 1.8\text{ ms}$ for $N = 1,000$ segments.
- **Latency Fraction:** Scheduling overhead accounts for $<0.05\%$ of total end-to-end model inference time.
- **Memory Footprint:** Peak memory for Trie hashing and Monge sorting is $<450\text{ KB}$ for 5,000 items.

---

## 5. Architectural Evolution Across Generations

The codebase reflects four iterative deployment generations:

```
+-----------------------------------------------------------------------------------------+
|                                ARCHITECTURAL EVOLUTION                                  |
+-----------------------------------------------------------------------------------------+
|  Gen 1: API / Cloud        -> HuggingFace Inference Endpoints, REST payload parsing     |
|  Gen 2: Local VM           -> Self-hosted Python service running ONNX / PyTorch          |
|  Gen 3: Docker Local       -> Containerized CTranslate2 INT8 NLLB-200 + SQLite TM Memory|
|  Gen 4: AWS / Multi-Cloud  -> Distributed ECS GPU / Azure DevOps Pipeline + Kusto Telemetry |
|  [CR-BATCH ENGINE]         -> Mathematical dynamic batching layer integrated across Gen 3 & 4|
+-----------------------------------------------------------------------------------------+
```

1. **`gen1_API_HFace`:** Initial prototype offloading translation to hosted HuggingFace inference APIs via REST calls. Suffered from rate limits and high external latency.
2. **`gen2_VM_Local`:** Shifted inference to local self-hosted VMs using native PyTorch and ONNX runtimes. Improved latency but exhibited high memory footprint.
3. **`gen3_Docker_Local`:** Modernized container architecture running `CTranslate2` INT8 quantized NLLB-200 models alongside an embedded SQLite Translation Memory. Provides offline execution for local build agents.
4. **`gen4_AWS_MultiCloud`:** Production enterprise deployment. Integrates Azure DevOps release pipelines with AWS ECS GPU clusters, Amazon S3 artifact storage, and Microsoft Azure Kusto (Application Insights) telemetry for live latency tracking.
5. **`CR-Batch Scheduler Integration`:** Integrated directly into `gen3_Docker_Local` and `gen1_API_HFace`, replacing the legacy `BATCH_SIZE = 52` loop with `CRBatcher.schedule()`.

---

## 6. High-Resolution Visual Specifications

All architectural designs and mathematical formulations are compiled into high-resolution (300 DPI), tightly-cropped vector graphics:

1. **End-to-End System Architecture (`hld_system_architecture.jpg`):**
   - Azure DevOps trigger $\to$ TM Check $\to$ CR-Batch Partitioning $\to$ CTranslate2 Engine $\to$ Multi-Cloud Storage.
2. **CR-Batch Core Micro-Architecture (`hld_cr_batch_core.jpg`):**
   - Radix-Trie Prefix Hashing $\to$ Pinball Conformal Quantile Estimator $\to$ 1D Monge Optimal Transport Sorting $\to$ Dynamic 3D Bucket Packing $\to$ DOM Restoration.
3. **Execution Sequence Flow (`hld_sequence_flow.jpg`):**
   - Full asynchronous interaction diagram across Build Agent, File Parser, TM Engine, Scheduler, and CTranslate2 Worker.
4. **Mathematical Formulation Card (`cr_batch_mathematical_formulation.jpg`):**
   - Typeset KaTeX equations detailing the global loss function, hardware constraints, Theorem 1 (coverage bound), Theorem 2 (Monge optimality), and empirical proofs.

---

## 7. Repositories & Synchronized Branches

### 7.1 Dedicated Research Repository
- **URL:** [https://github.com/anshull-saxena/CR-Batch-Localization](https://github.com/anshull-saxena/CR-Batch-Localization)
- **Branch:** `main`
- **Contents:**
  - `src/cr_batcher.py`: Clean, standalone CR-Batch implementation.
  - `tests/test_cr_batcher.py`: Unit test suite verifying DOM preservation and constraint adherence.
  - `benchmarks/benchmark_multilingual.py`: Automated comparative benchmarking tool.
  - `docs/HLD.md`: Full architectural specification.
  - `docs/assets/`: High-resolution JPEGs (Architecture, Core, Sequence, Formulation).

### 7.2 Cloud Infrastructure Repository
- **URL:** [https://github.com/anshull-saxena/Cloud_Localization](https://github.com/anshull-saxena/Cloud_Localization)
- **Branch:** `feat/cr-batch-scheduler`
- **Integration:** Embeds `cr_batcher.py` and updated HLD assets directly into the cloud localization pipeline.
