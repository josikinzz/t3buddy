# Local Model Benchmarks

A side-by-side benchmark comparison of the 13 LLMs currently installed for local use via Ollama.

_Last updated: 2026-06-28_

These are the user's 13 installed Ollama models, compared on the most broadly-shared benchmarks. Scores are taken from official model cards / papers and reputable third-party leaderboards (Artificial Analysis, LMArena, llm-stats, and others). **All published scores reflect full-precision (BF16/FP8) weights — the user's local quants (shown in each Ollama tag) will perform somewhat below these numbers, with the largest hits typically on hard math and coding.** Any number not confirmed against a primary source is marked **(unverified)** in the per-model tables and **(unv.)** in the master comparison table.

## At a glance

| Model (tag) | Params (total/active) | Type | Context | Quant size on disk | Best for |
| --- | --- | --- | --- | --- | --- |
| `glm-4.5-air:Q2_K` | 106B / 12B (MoE) | Reasoning + instruct + coder/agentic | 128K (131,072) | ~2-bit Q2_K GGUF | Efficient local agentic reasoning + coding/tool-use at modest active-param cost |
| `deepseek-r1-distill-llama-70b:q4_K_M` | 70.6B dense | Reasoning | 128K | ~40–43 GB | Strong local math/reasoning + competitive coding at 70B scale, near-full-precision at q4 |
| `qwen3-next-80b-instruct:q4_K_M` | 80B / ~3B (MoE) | Instruct (non-thinking) | 256K (262,144), ~1M YaRN | ~46–48.5 GB | General-purpose long-context assistant, coding + instruction-following at ~3B-active speed |
| `qwen3-next-80b-thinking:q4_K_M` | 80B / ~3B (MoE) | Reasoning (thinking) | 256K (262,144), ~1M YaRN | ~46–48.5 GB | Memory-efficient long-context reasoning, math, and agentic/tool-use |
| `gemma4-heretic-uncensored:31b-q8_0` | 30.7B dense | Multimodal instruct (abliterated/uncensored) | 256K | ~33 GB (q8_0) | Uncensored creative writing, roleplay, fiction, coding near base Gemma 4 31B quality |
| `qwen3-coder-next:q4_K_M` | 80B / 3B (MoE) | Coder (agentic, non-thinking) | 256K (262,144), toward ~1M | ~52 GB | High-throughput long-context agentic coding (repo-scale SWE-bench, tool-calling) |
| `glm-4.7-flash:q4_K_M` | ~30–31B / ~3B (MoE) | Reasoning + coder/agentic | ~200K (198K Ollama) | ~18 GB | Low-VRAM (~18 GB) agentic coding + reasoning with long context; strongest open ~30B class |
| `gpt-oss:20b` | 20.9B / 3.61B (MoE, MXFP4) | Reasoning + agentic/coding | 128K (131,072) | ~14 GB (Ollama default) | Local/edge reasoning + agentic/coding on a single ~16 GB GPU, high effort with tools |
| `gpt-oss-abliterated:20b-q8_0` | 20.9B / 3.61B (MoE) | Reasoning + agentic/coding (abliterated/uncensored) | 128K (131,072) | ~22 GB (20.6 GiB, Q8_0) | Uncensored local reasoning/coding + unrestricted creative writing at near-base gpt-oss quality |
| `qwen3.6:latest` | 35B / ~3B (MoE) | Reasoning + coder, multimodal (text+image) | 256K (262,144), ~1M YaRN | ~24 GB | Local agentic coding + repo/frontend dev plus strong math reasoning at ~3B-active speed |
| `gemma4:latest` | ~4.5B effective (E4B) | Multimodal (text+image+audio) | 128K | ~9.6 GB | On-device/single-GPU multimodal where E4B punches above ~4.5B-effective weight |
| `deepseek-r1:32b` | 32.8B dense | Reasoning | 128K (131,072) | ~20 GB (Q4_K_M) | Local math, science (GPQA), competitive-coding reasoning on a single 24 GB GPU, ~lossless at Q4 |
| `qwen3-coder:30b` | 30.5B / 3.3B (MoE) | Coder (agentic, non-thinking) | 256K (262,144), 1M YaRN | ~17.7 GB | Local agentic coding + tool-use needing long-context repo understanding at low active-param cost |

## Master benchmark comparison

One row per model on the most broadly-shared benchmarks. "—" means no published number for that model. "(unv.)" marks values not confirmed against a primary source. For reasoning models that report effort-specific or "with tools" numbers, the headline (best / high-effort) value is shown. **For GPT-OSS, the high-effort, no-tools numbers are used in this table.**

| Model (tag) | MMLU-Pro | GPQA-Diamond | AIME | MATH-500 | LiveCodeBench | SWE-bench Verified | IFEval | Arena/LMArena Elo | AA Index |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `glm-4.5-air:Q2_K` | 81.4 | 75.0 | 89.4 (AIME 2024) | 98.1 | 70.7 | 57.6 | — | — | 64.8 [^aa-glm45air] |
| `deepseek-r1-distill-llama-70b:q4_K_M` | 71.2 (unv.) | 65.2 | 70.0 (AIME 2024) | 94.5 | 57.5 | — | — | — | ~10–16 (unv.) |
| `qwen3-next-80b-instruct:q4_K_M` | 80.6 | 72.9 | 69.5 (AIME 2025) | — | 56.6 (v6) | — | 87.6 | 1401 ±5 (LMArena) | 14 |
| `qwen3-next-80b-thinking:q4_K_M` | 82.7 | 77.2 | 87.8 (AIME 2025) | — | 68.7 (v6) | — | 88.9 | ~1370 (unv.) | 20 |
| `gemma4-heretic-uncensored:31b-q8_0` | 85.2 [^base-gemma] | 84.3 [^base-gemma] | 89.2 (AIME 2026, no tools) [^base-gemma] | — | 80.0 (v6) [^base-gemma] | — | — | ~1452 (unv.) [^base-gemma] | — |
| `qwen3-coder-next:q4_K_M` | 80.52 | 74.49 | 89.01 (AIME 2024) | — | 58.93 (v6) | 71.3 [^scaffold-cn] | — | — | ~21–28 (unv.) |
| `glm-4.7-flash:q4_K_M` | — | 75.2 | 91.6 (AIME 2025) | — | 64.0 (v6) | 59.2 | — | — | 16 (unv.) |
| `gpt-oss:20b` | 73.6 [^cm-gptoss] | 71.5 (no tools) | 92.1 (AIME 2024, no tools) [^he-gptoss] | — | — | 60.7 | — | 1318 ±6.4 (unv.) | 15 (high) |
| `gpt-oss-abliterated:20b-q8_0` | 73.6 [^abl-gptoss] | 71.5 (no tools) [^abl-gptoss] | 92.1 (AIME 2024, no tools) [^abl-gptoss] | — | — | 60.7 [^abl-gptoss] | — | 1318 ±6.4 (unv.) [^abl-gptoss] | 15 (high) [^abl-gptoss] |
| `qwen3.6:latest` | 85.2 | 86.0 | 92.7 (AIME 2026) | — | 80.4 (v6) | — | — | — | 32 |
| `gemma4:latest` | 69.4 | 58.6 | 42.5 (AIME 2026, no tools) | — | 52.0 (v6) | — | — | — | ~12 (unv.) |
| `deepseek-r1:32b` | low (unv.) | 62.1 | 72.6 (AIME 2024) | 94.3 | 57.2 | — | 72.5 (unv.) | — | 11 (unv.) |
| `qwen3-coder:30b` | — | — | — | — | — | 51.6 [^scaffold-c30] | — | — | 14 |

[^aa-glm45air]: GLM-4.5-Air "AA-Index" 64.8 is the value from the official tech report table; Artificial Analysis' own third-party Intelligence Index for this model is ~17 (estimated). The 64.8 figure is shown here as the official-table number.
[^base-gemma]: Gemma 4 31B numbers are for the **base** `google/gemma-4-31b-it` model; the abliterated "heretic" finetune publishes no capability benchmarks. LMArena Elo ~1452 is for the base 31B (exact Elo unverified).
[^scaffold-cn]: Qwen3-Coder-Next SWE-bench Verified varies by scaffold: 70.6% (SWE-Agent), 71.1% (MiniSWE-Agent), 71.3% (OpenHands). Headline best (71.3, OpenHands) shown.
[^cm-gptoss]: GPT-OSS MMLU-Pro 73.6 is an HF community eval (reasoning effort not stated); the OpenAI card does not report MMLU-Pro.
[^he-gptoss]: GPT-OSS values are high-effort, no-tools where applicable. AIME 2025 (no tools, high) is 91.7; AIME 2024 (no tools, high) 92.1 shown. With tools the numbers are higher (e.g. AIME 2025 with tools 98.7).
[^scaffold-c30]: Qwen3-Coder-30B SWE-bench Verified 51.6 is Qwen-reported (OpenHands, 100 turns) from HF discussion #30.
[^abl-gptoss]: These are **base** `openai/gpt-oss-20b` numbers (identical to the `gpt-oss:20b` row, high-effort/no-tools where applicable); the abliterated/uncensored NEO-Imatrix finetune (DavidAU, on Huihui-ai's BF16-abliterated base) publishes no separate capability benchmarks. Abliteration removes refusals but typically costs a few points on some reasoning/IF benchmarks (GSM8K-style math most sensitive), so treat these as an upper bound. Local quant here is Q8_0 (near-lossless vs the abliterated weights).

## How to read this

- **MoE active-param speed.** Several models are sparse Mixture-of-Experts: total parameters set the memory/disk footprint, but only the *active* params run per token, so inference speed tracks the active count (e.g. ~3B-active MoEs run far faster than their total size suggests).
- **Quant impact.** Every published number above is full-precision. The user runs quantized GGUFs (the suffix in each tag). Higher-bit quants (q8_0, q5/q4_K_M) lose little; an aggressive ~2-bit quant (Q2_K, used here for GLM-4.5-Air) can lose meaningfully on reasoning/coding/long-context. Hard math and coding degrade first.
- **Reasoning vs instruct.** "Thinking"/reasoning models emit explicit chains-of-thought and score much higher on math/reasoning but are slower and more verbose; "instruct"/non-thinking models are faster and better for direct chat and many coding/agentic tasks.
- **Not always apples-to-apples.** Some 2026 models report newer benchmark suites (AIME 2026, HMMT 2025/2026, LiveCodeBench v6, SWE-bench Pro) instead of, or alongside, the older ones. The AIME year is noted in each cell; columns aren't always directly comparable across model generations.

---

## GLM-4.5-Air

**Ollama tag:** `glm-4.5-air:Q2_K`

GLM-4.5-Air is an open-weight (MIT) hybrid-reasoning MoE from Zhipu AI / Z.ai, released Jul 28–Aug 8 2025. 106B total params, 12B active (128 routed experts + shared, ~8–9 activated), 128K context (131,072), up to 96K output. Compact sibling of GLM-4.5 (355B/32B); base + thinking/non-thinking instruct; targets Agentic/Reasoning/Coding. The user's Q2_K GGUF is an aggressive ~2-bit local quant.

| Benchmark | Score | Source |
| --- | --- | --- |
| MMLU-Pro | 81.4 | Official model card / tech report (via llm-stats, Artificial Analysis) |
| GPQA (Diamond) | 75.0 | Official tech report (llm-stats); HF card lists 71.72 (variant) |
| AIME 2024 | 89.4 | Official tech report (llm-stats) |
| MATH-500 | 98.1 | Official tech report (llm-stats) |
| LiveCodeBench | 70.7 | Official tech report (llm-stats) |
| SWE-bench Verified | 57.6 | Official tech report (llm-stats) |
| Terminal-Bench | 30.0 | Official tech report (llm-stats) |
| TAU-bench (Retail) | 77.9 | Official tech report (llm-stats) |
| TAU-bench (Airline) | 60.8 | Official tech report (llm-stats) |
| BFCL-v3 | 76.4 | Official tech report (llm-stats) |
| BrowseComp | 21.3 | Official tech report (llm-stats) |
| SciCode | 37.3 | Official tech report (llm-stats) |
| Humanity's Last Exam (HLE) | 10.6 | Official tech report (llm-stats); HF card 8.12 (variant) |
| AA-Index (official table) | 64.8 | Official tech report (llm-stats) |
| Overall avg across 12 benchmarks | 59.8 | Official GLM-4.5 GitHub / blog |
| Artificial Analysis Intelligence Index | 17 (estimated) | Artificial Analysis (third-party) |
| AIME 2025 | not separately published for Air (unverified) | — |
| MMLU / GSM8K / HumanEval / MBPP / BBH / DROP / IFEval / MT-Bench / Arena-Hard / AlpacaEval / GAIA / LMArena Elo | not published for GLM-4.5-Air (unverified) | — |

**Quant impact (Q2_K):** Most aggressive practical quant (~2-bit), an emergency/low-VRAM option with meaningful quality loss vs reference; published scores are full-precision. Unsloth dynamic Q2_K_XL cuts KL-divergence ~7.5% vs naive Q2_K; expect the largest hits on reasoning/coding/long-context. (Vendor-specific Q2_K scores unverified.)

**Best for:** Efficient local/agentic reasoning + coding and tool-use at modest active-param cost; treat published scores as full-precision references a Q2_K quant will underperform.

**Sources:**
- https://huggingface.co/zai-org/GLM-4.5-Air
- https://github.com/zai-org/GLM-4.5
- https://arxiv.org/abs/2508.06471
- https://docs.z.ai/guides/llm/glm-4.5
- https://llm-stats.com/models/glm-4.5-air
- https://llm-stats.com/models/compare/glm-4.5-vs-glm-4.5-air
- https://artificialanalysis.ai/models/glm-4-5-air
- https://huggingface.co/unsloth/GLM-4.5-Air-GGUF
- https://unsloth.ai/docs/basics/unsloth-dynamic-2.0-ggufs

---

## DeepSeek-R1-Distill-Llama-70B

**Ollama tag:** `deepseek-r1-distill-llama-70b:q4_K_M`

Dense 70B reasoning model = Llama-3.3-70B-Instruct fine-tuned on ~800K R1 reasoning samples. ~70.6B params (BF16), 128K context, released Jan 20–22 2025 (arXiv:2501.12948). Emits `<think>` chains. Official evals: 32,768 max gen, temp 0.6, top-p 0.95, pass@1 over 64 samples. q4_K_M GGUF ~40–43 GB.

| Benchmark | Score | Source |
| --- | --- | --- |
| AIME 2024 (pass@1) | 70.0 | Official model card / R1 paper |
| AIME 2024 (cons@64) | 86.7 | Official model card / R1 paper |
| MATH-500 (pass@1) | 94.5 | Official model card / R1 paper |
| GPQA Diamond (pass@1) | 65.2 | Official model card / R1 paper |
| LiveCodeBench (pass@1) | 57.5 | Official model card / R1 paper |
| Codeforces (rating) | 1633 | Official model card / R1 paper |
| MMLU (5-shot) | 78.04 | RedHatAI eval (BF16 base) |
| GSM8K (strict, 5-shot) | 93.03 | RedHatAI eval (BF16 base) |
| ARC-Challenge (25-shot) | 63.65 | RedHatAI eval (BF16 base) |
| HellaSwag (10-shot) | 84.85 | RedHatAI eval (BF16 base) |
| Winogrande (5-shot) | 78.22 | RedHatAI eval (BF16 base) |
| TruthfulQA (MC2) | 56.67 | RedHatAI eval (BF16 base) |
| OpenLLM V1 average | 75.74 | RedHatAI eval (BF16 base) |
| MMLU-Pro | 71.2 (unverified) | designforonline.com aggregator |
| Artificial Analysis Intelligence Index | ~10–16 (unverified) | Artificial Analysis (estimated) |
| AIME 2025 | not reliably published (unverified) | — |
| HumanEval / MBPP / SWE-bench / BBH / IFEval / LMArena Elo | no official numbers (unverified) | — |

**Quant impact (q4_K_M):** Minimal. RedHatAI INT4 (w4a16) recovered ~100.2% of BF16 OpenLLM-V1 avg (MMLU 98.9%, GSM8K 100%). q4_K_M is closely comparable. No significant reasoning degradation vs FP8 reported.

**Best for:** Strong local math/reasoning (AIME, MATH-500) and competitive coding at 70B scale, ~48 GB VRAM via q4_K_M with near-full-precision quality.

**Sources:**
- https://huggingface.co/deepseek-ai/DeepSeek-R1-Distill-Llama-70B
- https://arxiv.org/html/2501.12948v1
- https://huggingface.co/RedHatAI/DeepSeek-R1-Distill-Llama-70B-quantized.w4a16
- https://artificialanalysis.ai/models/deepseek-r1-distill-llama-70b
- https://llm-stats.com/models/deepseek-r1-distill-llama-70b
- https://huggingface.co/lmstudio-community/DeepSeek-R1-Distill-Llama-70B-GGUF
- https://designforonline.com/ai-models/deepseek-r1-distill-llama-70b/ (MMLU-Pro, unverified)

---

## Qwen3-Next-80B-A3B-Instruct

**Ollama tag:** `qwen3-next-80b-instruct:q4_K_M`

Qwen Team (Alibaba), released Sep 2025. 80B-total / ~3B-active sparse MoE (512 experts, 10 routed + 1 shared), hybrid attention (3:1 Gated DeltaNet : Gated Attention) + Multi-Token Prediction. Native 262,144 (256K) context, ~1M via YaRN. Instruct = non-thinking variant. All official scores full-precision.

| Benchmark | Score | Source |
| --- | --- | --- |
| MMLU-Pro | 80.6 | Qwen official (HF card) |
| MMLU-Redux | 90.9 | Qwen official (HF card) |
| GPQA (Diamond) | 72.9 | Qwen official (HF card) |
| SuperGPQA | 58.8 | Qwen official (HF card) |
| AIME 2025 | 69.5 | Qwen official (HF card) |
| HMMT 2025 | 54.1 | Qwen official (HF card) |
| LiveBench (2024-11-25) | 75.8 | Qwen official (HF card) |
| LiveCodeBench v6 | 56.6 | Qwen official (HF card) |
| MultiPL-E | 87.8 | Qwen official (HF card) |
| Aider-Polyglot | 49.8 | Qwen official (HF card); Aider via llm-stats (0.498) |
| IFEval | 87.6 | Qwen official (HF card) |
| Arena-Hard v2 | 82.7 | Qwen official (HF card) |
| Creative Writing v3 | 85.3 | Qwen official (HF card) |
| WritingBench | 87.3 | Qwen official (HF card) |
| BFCL-v3 (tool use) | 70.3 | Qwen official (HF card) |
| MultiIF | 75.8 | Qwen official (HF card) |
| MMLU-ProX | 76.7 | Qwen official (HF card) |
| INCLUDE | 78.9 | Qwen official (HF card) |
| PolyMATH | 45.9 | Qwen official (HF card) |
| RULER (avg, to 1M ctx) | 91.8 | Qwen official (HF card) |
| RULER @ 1M tokens | 80.3 | Qwen official (HF card) |
| LMArena Chatbot Arena (Text Elo) | 1401 ±5 (rank ~#53) | LMArena (datalearner/lmmarketcap mirrors) |
| Artificial Analysis Intelligence Index (v4.1) | 14 (#6/39 in class) | Artificial Analysis |

Not reported by Qwen (don't attribute): plain MMLU, AIME 2024, GSM8K, MATH-500, HumanEval, MBPP, BigCodeBench, SWE-bench Verified.

**Quant impact (q4_K_M):** No model-specific numbers. Unsloth recommends UD-Q4_K_XL (~46.1 GB) over Q4_K_M (~48.5 GB). General Q4_K_M ~97–99.5% of FP16; IFEval shows largest drop (~−6.6 pts in one study). Caveat: needs recent llama.cpp (Gated DeltaNet support PR #16095 merged Nov 28 2025; a Dec 2025 imatrix regression caused repetition loops on Q4_K_M, re-fixed ~Jan 12 2026) — use post-Jan-2026 builds.

**Best for:** Strong general-purpose local assistant — excellent long-context (256K–1M), coding, instruction-following at ~3B active-param speed.

**Sources:**
- https://huggingface.co/Qwen/Qwen3-Next-80B-A3B-Instruct
- https://www.alibabacloud.com/blog/602536
- https://qwen.ai/blog?id=4074cca80393150c248e508aa62983f9cb7d27cd
- https://artificialanalysis.ai/models/qwen3-next-80b-a3b-instruct
- https://www.datalearner.com/en/leaderboards/external/text-generation
- https://llm-stats.com/benchmarks/aider-polyglot
- https://huggingface.co/unsloth/Qwen3-Next-80B-A3B-Instruct-GGUF
- https://github.com/ggml-org/llama.cpp/pull/16095

---

## Qwen3-Next-80B-A3B-Thinking

**Ollama tag:** `qwen3-next-80b-thinking:q4_K_M`

Qwen Team (Alibaba), released Sep 11 2025 (Apache 2.0). Reasoning variant of Qwen3-Next. ~80B total / ~3B active MoE (512 experts, 10 routed + 1 shared, 48 layers), hybrid linear attention (Gated DeltaNet + Gated Attention). Native 262,144 context, ~1M via YaRN. Thinking-only mode. Beats Gemini-2.5-Flash-Thinking on several benchmarks per Qwen.

| Benchmark | Score | Source |
| --- | --- | --- |
| AIME 2025 | 87.8 | Qwen HF model card |
| HMMT 2025 | 73.9 | Qwen HF model card |
| PolyMATH | 56.3 | Qwen HF model card |
| GPQA (Diamond) | 77.2 | Qwen HF model card |
| SuperGPQA | 60.8 | Qwen HF model card |
| MMLU-Pro | 82.7 | Qwen HF model card |
| MMLU-Redux | 92.5 | Qwen HF model card |
| MMLU-ProX | 78.7 | Qwen HF model card |
| INCLUDE | 78.9 | Qwen HF model card |
| LiveCodeBench v6 (25.02–25.05) | 68.7 | Qwen HF model card |
| CFEval (Codeforces Elo) | 2071 | Qwen HF model card |
| OJBench | 29.7 | Qwen HF model card |
| LiveBench (2024-11-25) | 76.6 | Qwen HF model card |
| Arena-Hard v2 | 62.3 | Qwen HF model card |
| IFEval | 88.9 | Qwen HF model card |
| WritingBench | 84.6 | Qwen HF model card |
| MultiIF | 77.8 | Qwen HF model card |
| BFCL-v3 (tool use) | 72.0 | Qwen HF model card |
| TAU1-Retail / TAU1-Airline | 69.6 / 49.0 | Qwen HF model card |
| TAU2-Retail / Airline / Telecom | 67.8 / 60.5 / 43.9 | Qwen HF model card |
| Artificial Analysis Intelligence Index | 20 (#9/62) | Artificial Analysis |
| AA output speed | 177.6 tok/s | Artificial Analysis |
| LMArena Elo | ~1370 (unverified) | search aggregation |

Not on official card: AIME 2024, MATH-500, SWE-bench Verified, BigCodeBench, RULER (treat external figures as unverified).

**Quant impact (q4_K_M):** No official table. Comparable A3B MoE: q4_K_M ppl ~0.027 above q5_K_M, ~99.9% KL retention with Unsloth Dynamic 2.0; minor loss most visible on hard math (unverified for this exact model).

**Best for:** Local memory-efficient long-context reasoning, math, and agentic/tool-use where ~3B-active speed matters but near-frontier open reasoning quality is desired.

**Sources:**
- https://huggingface.co/Qwen/Qwen3-Next-80B-A3B-Thinking
- https://huggingface.co/Qwen/Qwen3-Next-80B-A3B-Thinking-FP8
- https://artificialanalysis.ai/models/qwen3-next-80b-a3b-reasoning
- https://build.nvidia.com/qwen/qwen3-next-80b-a3b-thinking/modelcard
- https://unsloth.ai/docs/models/tutorials/qwen3-next
- https://kaitchup.substack.com/p/running-qwen3-next-hybrid-attention
- https://llm-stats.com/models/qwen3-next-80b-a3b-thinking

---

## Gemma 4 31B (abliterated/uncensored finetune)

**Ollama tag:** `gemma4-heretic-uncensored:31b-q8_0`

Community "heretic"/abliterated (uncensored) build of Google DeepMind's Gemma 4 31B Instruct (`google/gemma-4-31b-it`). Base: 30.7B dense transformer, hybrid attention (local sliding-window + global), 256K context, multimodal (text+image, video via frames), Apache 2.0, released Apr 2 2026, training cutoff Jan 2025. "Heretic" = Philipp Emanuel Weidmann's automatic abliteration tool (TPE/Optuna optimizer minimizing refusals + KL-divergence). q8_0 build (~33 GB) = `pmarreck/gemma4-heretical` wrapping `trohrbaugh/gemma-4-31b-it-heretic-ara` (Arbitrary-Rank Ablation, layers 2–60).

| Benchmark | Score | Source | Notes |
| --- | --- | --- | --- |
| Refusal rate (after) | 5/100 (was 98/100) | trohrbaugh HF / pmarreck GitHub | finetune-specific |
| KL-divergence vs base | 0.012 | trohrbaugh HF / pmarreck GitHub | finetune-specific |
| Capability benchmarks for finetune | None published | trohrbaugh HF | finetune-specific |
| MMLU-Pro | 85.2% | Gemma 4 model card | base model (31B) |
| GPQA Diamond | 84.3% | Gemma 4 model card | base model |
| LiveCodeBench v6 | 80.0% | Gemma 4 model card | base model |
| AIME 2026 (no tools) | 89.2% | Gemma 4 model card | base model |
| MATH-Vision | 85.6% | Gemma 4 model card | base model (multimodal) |
| BigBench Extra Hard | 74.4% | Gemma 4 model card | base model |
| MMMLU (multilingual MMLU) | 88.4% | Gemma 4 model card | base model |
| MMMU Pro (Vision) | 76.9% | Gemma 4 model card | base model (multimodal) |
| MRCR v2 (long context) | 66.4% | Gemma 4 model card | base model |
| LMArena Text Elo | ~1452 (#3 open, #1 US open) | Google blog / Arena.ai | base model (unverified exact Elo) |
| GSM8K / standard MATH / HumanEval / IFEval | Not reported by Google | Gemma 4 model card | base model |

**Abliteration degradation:** Heretic emphasizes low KL (0.012) over capability loss, but a comparative study (arXiv 2512.13655) finds abliteration generally degrades benchmarks slightly, with GSM8K math reasoning most sensitive. No degradation numbers for this specific finetune.

**Best for:** Uncensored creative writing, roleplay, fiction, and coding wanting near-base Gemma 4 31B quality with refusals removed — not for verified math/reasoning-critical work.

**Sources:**
- https://ai.google.dev/gemma/docs/core/model_card_4
- https://blog.google/innovation-and-ai/technology/developers-tools/gemma-4/
- https://huggingface.co/trohrbaugh/gemma-4-31b-it-heretic-ara
- https://github.com/pmarreck/gemma4-heretical
- https://github.com/p-e-w/heretic
- https://arxiv.org/pdf/2512.13655

_Note: no HF card literally named gemma4-heretic-uncensored; specs match the pmarreck/trohrbaugh build (probable, not certain, origin)._

---

## Qwen3-Coder-Next

**Ollama tag:** `qwen3-coder-next:q4_K_M`

Open-weight (Apache 2.0) agentic coding model, Qwen Team (Alibaba), released Feb 4 2026 (tech report arXiv:2603.00729). Base = Qwen3-Next-80B-A3B-Base. Ultra-sparse MoE: 80B total / 3B active (512 experts, 10 + 1 shared), hybrid (Gated DeltaNet + Gated Attention, 48 layers), 262,144 native context (toward ~1M), non-thinking only, ~370 languages. q4_K_M GGUF ~52 GB.

| Benchmark | Score | Source |
| --- | --- | --- |
| SWE-bench Verified (SWE-Agent) | 70.6% | Qwen tech report (arXiv 2603.00729) |
| SWE-bench Verified (MiniSWE-Agent) | 71.1% | Qwen tech report |
| SWE-bench Verified (OpenHands) | 71.3% | Qwen tech report |
| SWE-bench Multilingual | 62.8% | Qwen tech report |
| SWE-bench Pro (SWE-Agent) | 56.2% | Qwen tech report |
| SWE-bench Pro (HF card label) | 44.3% | HF model card |
| Terminal-Bench 2.0 (best scaffold) | 36.2% | Qwen tech report / HF card |
| LiveCodeBench v6 | 58.93% | Qwen tech report |
| Aider Polyglot | 66.20% | Qwen tech report (Qwen's own measurement; not on aider.chat leaderboard) |
| Codeforces (rating) | 2100 | Qwen tech report |
| OJBench | 23.01 | Qwen tech report |
| EvalPlus | 86.56% | Qwen tech report |
| MultiPL-E | 88.23% | Qwen tech report |
| CRUXEval | 95.88% | Qwen tech report |
| Spider (text-to-SQL) | 83.66% | Qwen tech report |
| BIRD-SQL | 63.56% | Qwen tech report |
| FullStackBench (en / zh) | 60.58% / 57.38% | Qwen tech report |
| Tool-call format following (avg, 5 scaffolds) | 92.7% | Qwen tech report |
| SecCodeBench | 61.2% | Qwen / Winbuzzer |
| CWEval (func-sec@1) | 56.32% | Qwen / Winbuzzer |
| MMLU | 87.73% | Qwen tech report |
| MMLU-Redux | 91.18% | Qwen tech report |
| MMLU-Pro | 80.52% | Qwen tech report |
| GPQA | 74.49% | Qwen tech report |
| SuperGPQA | 57.45% | Qwen tech report |
| AIME24 | 89.01% | Qwen tech report |
| AIME25 | 83.07% | Qwen tech report |
| HMMT25 (Feb / Nov) | 70.21% / 75.57% | Qwen tech report |
| Artificial Analysis Intelligence Index | ~21–28 (unverified) | Artificial Analysis |

Not reported: BigCodeBench, HumanEval/+, MBPP/+, BFCL, Arena-Hard, LMArena Elo.

**Quant impact (q4_K_M):** No model-specific numbers. q4_K_M largely preserves code-gen (~parity with AWQ on HumanEval in comparable Qwen tests); 1–3% loss mainly on numerical/math; Q5_K_M/imatrix recommended for math-heavy work (unverified for this model).

**Best for:** Local high-throughput long-context agentic coding (repo-scale SWE-bench tasks, tool-calling in Claude Code/Cline/Qwen Code); less suited to heavy math precision at q4_K_M.

**Sources:**
- https://qwen.ai/blog?id=qwen3-coder-next
- https://huggingface.co/Qwen/Qwen3-Coder-Next
- https://arxiv.org/html/2603.00729v1
- https://ollama.com/library/qwen3-coder-next
- https://winbuzzer.com/2026/02/04/alibaba-qwen3-coder-next-open-source-sparse-moe-coding-model-xcxwbn/
- https://artificialanalysis.ai/models/qwen3-coder-next
- https://aider.chat/docs/leaderboards/
- https://unsloth.ai/docs/models/qwen3-coder-next

---

## GLM-4.7-Flash

**Ollama tag:** `glm-4.7-flash:q4_K_M`

Real open-weights (MIT) model from Z.ai (Zhipu AI). 30B-A3B MoE (~30–31B total, ~3B active), ~200K context (official docs; HF config caps gen at 131K; Ollama lists 198K), hybrid "Preserved Thinking" reasoning. Lightweight sibling of flagship GLM-4.7 (358B MoE). Release date disputed (family Dec 22–23 2025; Flash-specific Jan 19 2026, unverified). q4_K_M ~18 GB; needs ~20–24 GB VRAM or runs CPU/RAM (only ~3B active).

| Benchmark | Score | Source |
| --- | --- | --- |
| AIME 2025 | 91.6 | HF zai-org/GLM-4.7-Flash card |
| GPQA-Diamond | 75.2 | HF zai-org/GLM-4.7-Flash card |
| LiveCodeBench v6 | 64.0 | HF zai-org/GLM-4.7-Flash card; llm-stats |
| HLE (Humanity's Last Exam) | 14.4 | HF zai-org/GLM-4.7-Flash card |
| SWE-bench Verified | 59.2 | HF zai-org/GLM-4.7-Flash card |
| τ²-Bench (tau-bench) | 79.5 | HF zai-org/GLM-4.7-Flash card |
| BrowseComp | 42.8 | HF zai-org/GLM-4.7-Flash card |
| Artificial Analysis Intelligence Index (non-reasoning) | 16 (#9/74) provisional estimate (unverified) | artificialanalysis.ai |
| HumanEval Pass@1 (q4_K_M, community, no FP baseline) | ~37.2% (unverified) | unsloth GGUF discussions #22 |

Z.ai did NOT publish for Flash: MMLU/MMLU-Pro, AIME 2024, MATH-500, BigCodeBench, HumanEval, Terminal-Bench, BFCL, Arena-Hard, IFEval. Flash absent from LMArena (no Elo), official Aider leaderboard, LiveBench.

For context, full GLM-4.7 (not Flash): MMLU-Pro 84.3 · GPQA-Diamond 85.7 · AIME 2025 95.7 · LiveCodeBench v6 84.9 · SWE-bench Verified 73.8 · SWE-bench Multilingual 66.7 · Terminal-Bench 2.0 41.0 · τ²-Bench 87.4 · BrowseComp 52.0 · HLE 24.8; AA Index 34 (live)/42 (launch) (unverified); LMArena ~1443 via BenchLM (unverified).

**Quant impact (q4_K_M):** No GLM-specific ppl-vs-FP measurement. MoE consensus: q4_K_M ≈ +0.05 ppl / ~1–3% loss; recommended floor for MoE (below it, router quality degrades). Community HumanEval sweep inconclusive.

**Best for:** Local low-VRAM (~18 GB) agentic coding and reasoning with long context — strongest open model in the ~30B class, accepting a capability gap vs the 358B flagship.

**Sources:**
- https://huggingface.co/zai-org/GLM-4.7-Flash
- https://huggingface.co/zai-org/GLM-4.7
- https://ollama.com/library/glm-4.7-flash
- https://docs.z.ai/guides/llm/glm-4.7
- https://www.zhipuai.cn/en/news/148
- https://www.marktechpost.com/2026/01/20/zhipu-ai-releases-glm-4-7-flash-a-30b-a3b-moe-model-for-efficient-local-coding-and-agents/
- https://artificialanalysis.ai/models/glm-4-7-flash-non-reasoning
- https://benchlm.ai/models/glm-4-7
- https://huggingface.co/unsloth/GLM-4.7-Flash-GGUF

---

## GPT-OSS 20B

**Ollama tag:** `gpt-oss:20b`

OpenAI open-weight (Apache 2.0), released Aug 5 2025. MoE ~20.9B total / ~3.61B active (32 experts, top-4, 24 layers, GQA alternating dense/sparse). Native MXFP4 (MoE weights 4.25 bits; attention/router/embeddings/LM head BF16), runs ~16 GB; Ollama default ~14 GB on disk. 131,072 (128k) context via YaRN. Reasoning-effort low/med/high in system prompt; headline numbers at high. All official evals on the MXFP4 model.

| Benchmark | Score (low/med/high) | Source |
| --- | --- | --- |
| MMLU | 80.4 / 84.0 / 85.3 | OpenAI model card, arXiv 2508.10925 Table 3 |
| MMMLU (multilingual avg) | 67.0 / 73.5 / 75.7 | OpenAI model card Table 3 |
| GPQA Diamond (no tools) | 56.8 / 66.0 / 71.5 | OpenAI model card Table 3 |
| GPQA Diamond (with tools) | 58.0 / 67.1 / 74.2 | OpenAI model card Table 3 |
| AIME 2024 (no tools) | 42.1 / 80.0 / 92.1 | OpenAI model card Table 3 |
| AIME 2024 (with tools) | 61.2 / 86.0 / 96.0 | OpenAI model card Table 3 |
| AIME 2025 (no tools) | 37.1 / 72.1 / 91.7 | OpenAI model card Table 3 |
| AIME 2025 (with tools) | 57.5 / 90.4 / 98.7 | OpenAI model card Table 3 |
| Humanity's Last Exam (no tools) | 4.2 / 7.0 / 10.9 | OpenAI model card Table 3 |
| Humanity's Last Exam (with tools) | 6.3 / 8.8 / 17.3 | OpenAI model card Table 3 |
| SWE-bench Verified | 37.4 / 53.2 / 60.7 | OpenAI model card Table 3 |
| Tau-Bench Retail | 35.0 / 47.3 / 54.8 | OpenAI model card Table 3 |
| Tau-Bench Airline | 32.0 / 42.6 / 38.0 (high non-monotonic) | OpenAI model card Table 3 |
| Aider Polyglot | 16.6 / 26.6 / 34.2 | OpenAI model card Table 3 |
| Codeforces Elo (no tools) | 1366 / 1998 / 2230 | OpenAI model card Table 3 |
| Codeforces Elo (with tools) | 1251 / 2064 / 2516 | OpenAI model card Table 3 |
| HealthBench | 40.4 / 41.8 / 42.5 | OpenAI model card Table 3 |
| HealthBench Hard | 9.0 / 12.9 / 10.8 (high non-monotonic) | OpenAI model card Table 3 |
| HealthBench Consensus | 84.9 / 83.0 / 82.6 | OpenAI model card Table 3 |
| MMLU-Pro | 73.6 (effort not stated) | HF community eval |
| GPQA Diamond (community) | 58.59 (medium, no tools) | HF community eval |
| Artificial Analysis Intelligence Index (v4.1) | 15 (high) / 14 (low) | Artificial Analysis |
| AA Index (Aug-2025 v3-era) | 48 (high) | Artificial Analysis launch article |
| MMLU (independent re-test) | 69 | arXiv 2508.12461 Table II |
| GSM8K (independent) | 78 | arXiv 2508.12461 Table II |
| HumanEval (independent) | 73 | arXiv 2508.12461 Table II |
| MedQA / LegalQA / FinQA (independent) | 62 / 65 / 68 | arXiv 2508.12461 |
| PIQA / SciQ (independent) | 74 / 75 | arXiv 2508.12461 |
| C-Eval (Chinese, independent) | 45 | arXiv 2508.12461 |
| LMArena Elo — Text overall | 1318 (±6.4) (unverified) | BenchLM scrape |
| LMArena Elo — Coding/Math/IF/Creative | 1370/1336/1281/1238 (unverified) | BenchLM scrape |

**Best for:** Local/edge reasoning and agentic/coding on a single ~16 GB GPU, especially at high reasoning effort with tools.

**Caveats:** The model card does NOT report MMLU-Pro, standalone MATH, MBPP, LiveCodeBench, BBH, IFEval. MXFP4: on non-Hopper/Blackwell GPUs weights dequantize to BF16 (~48 GB).

**Sources:**
- https://arxiv.org/html/2508.10925v1
- https://openai.com/index/gpt-oss-model-card/
- https://huggingface.co/openai/gpt-oss-20b
- https://github.com/openai/gpt-oss
- https://ollama.com/library/gpt-oss
- https://artificialanalysis.ai/models/gpt-oss-20b
- https://arxiv.org/abs/2508.12461
- https://benchlm.ai/models/gpt-oss-20b

---

## GPT-OSS 20B (abliterated/uncensored finetune)

**Ollama tag:** `gpt-oss-abliterated:20b-q8_0`

Uncensored/abliterated build of OpenAI's `gpt-oss-20b` (same MoE ~20.9B total / ~3.61B active, 24 layers, 128K context, harmony chat format). Lineage: OpenAI `gpt-oss-20b` → `huihui-ai/Huihui-gpt-oss-20b-BF16-abliterated` (refusal-direction abliteration on the BF16 weights, de-censors / removes refusals) → DavidAU `OpenAi-GPT-oss-20b-abliterated-uncensored-NEO-Imatrix-gguf` (NEO/CODE Imatrix-calibrated GGUF quants). The installed file is `OpenAI-20B-NEOPlus-Uncensored-Q8_0.gguf` (NEO/CODE Imatrix, Q8_0, ~20.6 GiB / ~22 GB on disk), imported with the same official harmony template + sampler defaults as `gpt-oss:20b`.

| Benchmark | Score | Source | Notes |
| --- | --- | --- | --- |
| Refusal behavior | De-censored (refusals removed) | huihui-ai base card / DavidAU card | finetune-specific (no numeric refusal rate published) |
| Capability benchmarks for finetune | None published | DavidAU / huihui-ai HF cards | finetune-specific |
| MMLU (low/med/high) | 80.4 / 84.0 / 85.3 | OpenAI model card Table 3 | base `gpt-oss-20b` |
| GPQA Diamond (no tools) | 56.8 / 66.0 / 71.5 | OpenAI model card Table 3 | base model |
| AIME 2024 (no tools) | 42.1 / 80.0 / 92.1 | OpenAI model card Table 3 | base model |
| AIME 2025 (no tools) | 37.1 / 72.1 / 91.7 | OpenAI model card Table 3 | base model |
| SWE-bench Verified | 37.4 / 53.2 / 60.7 | OpenAI model card Table 3 | base model |
| MMLU-Pro | 73.6 (effort not stated) | HF community eval | base model |
| AA Intelligence Index (v4.1) | 15 (high) / 14 (low) | Artificial Analysis | base model |
| LMArena Elo — Text overall | 1318 (±6.4) (unverified) | BenchLM scrape | base model |

**Abliteration degradation:** Abliteration removes safety refusals by ablating the refusal direction; a comparative study (arXiv 2512.13655) finds it generally degrades benchmarks slightly, with GSM8K-style math reasoning most sensitive. No degradation numbers are published for this specific finetune — base-model scores above are an upper bound. DavidAU notes the model can be "rough around the edges" from abliteration and recommends conservative sampler settings (see card) for stability.

**Best for:** Uncensored local reasoning, agentic/coding, and unrestricted creative writing wanting near-base gpt-oss-20b quality with refusals removed — not for verified safety-critical or refusal-dependent work. Runs alongside the stock `gpt-oss:20b` (keep both; this one trades a few points and refusal behavior for no guardrails, at higher-precision Q8_0).

**Sources:**
- https://huggingface.co/DavidAU/OpenAi-GPT-oss-20b-abliterated-uncensored-NEO-Imatrix-gguf
- https://huggingface.co/huihui-ai/Huihui-gpt-oss-20b-BF16-abliterated
- https://openai.com/index/gpt-oss-model-card/
- https://huggingface.co/openai/gpt-oss-20b
- https://arxiv.org/pdf/2512.13655

_Note: the abliterated finetune publishes no capability benchmarks; all numeric scores above are the base `gpt-oss-20b` values, repeated here for reference and marked as base-model in the Notes column._

---

## Qwen3.6-35B-A3B

**Ollama tag:** `qwen3.6:latest`

Alibaba Qwen, "Qwen3.6" generation, released Apr 2026. Tag `qwen3.6:latest` (~24 GB) = `qwen3.6:35b` = Qwen3.6-35B-A3B MoE (latest/35b/35b-a3b share hash 07d35212591f). ~35B total / ~3B active (256 experts, 8 routed + 1 shared), hybrid 40-layer Gated DeltaNet + Gated Attention with MoE FFNs, natively multimodal (text+image). 262,144 native context, ~1M via YaRN. Hybrid thinking model defaulting to thinking mode; "thinking preservation" across turns. Released Apr 16 2026 (dense 27B followed Apr 22 2026). NOTE: proprietary Qwen3.6-Plus/-Max (1M, ~78.8 SWE-bench) is a different closed model.

| Benchmark | Score | Source |
| --- | --- | --- |
| MMLU-Pro | 85.2 | Qwen HF card |
| MMLU-Redux | 93.3 | Qwen HF card |
| GPQA-Diamond | 86.0 | Qwen HF card |
| SuperGPQA | 64.7 | Qwen HF card |
| AIME 2026 | 92.7 | Qwen HF card |
| HMMT Feb 2025 | 90.7 | Qwen HF card |
| HMMT Nov 2025 | 89.1 | Qwen HF card |
| HMMT Feb 2026 | 83.6 | Qwen HF card |
| LiveCodeBench v6 | 80.4 | Qwen HF card |
| SWE-bench Verified | 73.4 | Qwen HF card / Lushbinary |
| SWE-bench Multilingual | 67.2 | Lushbinary |
| SWE-bench Pro | 49.5 | Qwen HF card |
| Terminal-Bench 2.0 | 51.5 | Lushbinary |
| Tau3-Bench (tool/agentic) | 67.2 | Qwen HF card (unverified — possibly TAU3 banking subset) |
| MCPMark (agentic) | 37.0 | Lushbinary |
| NL2Repo | 29.4 | Lushbinary |
| Artificial Analysis Intelligence Index | 32 (#3 in class) | Artificial Analysis |
| AA output speed | 163.2 tok/s | Artificial Analysis |
| 27B dense — MMLU-Pro | 86.2 | InsiderLLM (unverified) |
| 27B dense — GPQA-Diamond | 87.8 | InsiderLLM (unverified) |
| 27B dense — AIME 2026 | 94.1 | InsiderLLM (unverified) |
| 27B dense — HMMT Feb 2026 | 93.8 | InsiderLLM (unverified) |
| 27B dense — LiveCodeBench v6 | 83.9 | InsiderLLM (unverified) |
| 27B dense — SWE-bench Verified | 77.2 | InsiderLLM (unverified) |
| MMLU base / AIME 2024-2025 / MATH-500 / BigCodeBench / HumanEval / BFCL / Arena-Hard v2 / IFEval / Creative Writing / RULER / LMArena Elo | not published for 35B-A3B | — |

_Notes: AA figures conflict (page says 32; a secondary said 43 — used 32). 27B-dense numbers from InsiderLLM only, unverified._

**Best for:** Local agentic coding and repo-level/frontend dev plus strong math reasoning at ~3B-active speed in ~24 GB — punches above active-param size; general-chat leaderboards largely unmeasured.

**Sources:**
- https://ollama.com/library/qwen3.6
- https://huggingface.co/Qwen/Qwen3.6-35B-A3B
- https://github.com/QwenLM/Qwen3.6
- https://artificialanalysis.ai/models/qwen3-6-35b-a3b
- https://lushbinary.com/blog/qwen-3-6-developer-guide-benchmarks-architecture-api-self-hosting/
- https://insiderllm.com/guides/qwen-3-6-local-ai-guide/
- https://www.labellerr.com/blog/qwen3-6-35b-a3b-open-source-ai-model/

---

## Gemma 4 E4B

**Ollama tag:** `gemma4:latest`

Google DeepMind open-weight (Apache 2.0) family, released Apr 2 2026. Natively multimodal (text+image+video; edge sizes add audio; output text only). Sizes: E2B (~2.3B eff), E4B (~4.5B eff, ~8B w/ embeddings), 12B Unified (dense), 26B-A4B (MoE 25.2B/3.8B), 31B Dense (30.7B). Hybrid local-sliding-window + global attention. Context 128K (edge) up to 256K (12B/26B/31B). Ollama `gemma4:latest` (9.6 GB) = `gemma4:e4b` (E4B, ~4.5B eff, 128K, vision+audio). Scores below = E4B unless noted.

| Benchmark | Score | Source |
| --- | --- | --- |
| MMLU-Pro | 69.4% | Google model card / HF blog |
| GPQA Diamond | 58.6% | Google model card / HF blog |
| AIME 2026 (no tools) | 42.5% | Google model card / HF blog |
| LiveCodeBench v6 | 52.0% | Google model card / HF blog |
| Multilingual (Global MMLU / MMMLU) | 76.6% | Google model card |
| MMMU Pro (vision) | 52.6% | Google model card / HF blog |
| MATH-Vision (vision) | 59.5% | Google model card |
| MRCR v2 (8-needle, 128K) | 25.4% | HF blog |
| Artificial Analysis Intelligence Index | ~12 (estimated) | Artificial Analysis |
| GSM8K | ~85% (unverified — likely family/larger size) | gemma4.wiki secondary |
| HumanEval | ~85% (unverified — likely family/larger size) | gemmai4 secondary |
| IFEval / MBPP / BBH / DocVQA | not published for E4B (unverified) | — |
| LMArena/Chatbot Arena Elo | not published for E4B; Arena ranks 31B #3 (~1452) & 26B #6 (unverified) | Google blog / LMArena |

For reference, the 31B flagship (Google card): MMLU-Pro 85.2%, GPQA Diamond 84.3%, AIME 2026 89.2%, LiveCodeBench v6 80.0%, MMMU Pro 76.9%, multilingual 88.4%.

**Best for:** On-device/single-GPU multimodal (text+image+audio) at ~9.6 GB where E4B punches above ~4.5B-effective weight; step up to 26B/31B for top reasoning/coding.

**Sources:**
- https://blog.google/innovation-and-ai/technology/developers-tools/gemma-4/
- https://ai.google.dev/gemma/docs/core/model_card_4
- https://huggingface.co/blog/gemma4
- https://ollama.com/library/gemma4/tags
- https://artificialanalysis.ai/models/gemma-4-e4b

---

## DeepSeek-R1-Distill-Qwen-32B

**Ollama tag:** `deepseek-r1:32b`

Dense reasoning model from DeepSeek = Qwen2.5-32B fine-tuned on ~800k R1 reasoning samples. ~32.8B params (33B BF16), 131,072 (128K) context, recommended max gen 32,768, released Jan 22 2025 (arXiv 2501.12948). Ollama `deepseek-r1:32b` = this model, default Q4_K_M (~20 GB). Official card reports only a small subset for distilled models.

| Benchmark | Score | Source |
| --- | --- | --- |
| AIME 2024 (pass@1) | 72.6 | DeepSeek model card / R1 paper |
| AIME 2024 (cons@64) | 83.3 | DeepSeek model card / R1 paper |
| AIME 2025 | not officially published (unverified) | — |
| MATH-500 (pass@1) | 94.3 | DeepSeek model card / R1 paper |
| GPQA-Diamond (pass@1) | 62.1 | DeepSeek model card / R1 paper |
| LiveCodeBench (pass@1) | 57.2 | DeepSeek model card / R1 paper |
| Codeforces (rating) | 1691 | DeepSeek model card / R1 paper |
| Codeforces (percentile) | ~90th (unverified) | DeepSeek R1 paper |
| MMLU | ~73.9 (third-party) (unverified) | llm-stats.com |
| MMLU-Redux | 88.2 (unverified) | aggregator |
| MMLU-Pro | estimated low (unverified) | Artificial Analysis |
| GSM8K / HumanEval / BBH | not officially published for distill (unverified) | — |
| IFEval (strict prompt) | 72.5 (unverified; conflicting 83.9 seen) | aggregators |
| Arena-Hard | 60.8 (unverified) | aggregator |
| LiveBench (2024-11-25) | 72.0 (unverified) | aggregator |
| Artificial Analysis Intelligence Index | 11 (earlier "17" cited) (unverified) | Artificial Analysis |
| LMArena (Chatbot Arena) Elo | not officially listed (unverified) | — |

**Quant impact (Q4_K_M, Ollama default):** Essentially lossless. Study arXiv 2505.02390: Q4_K_M vs BF16 — MATH-500 93.90 vs 93.65, GPQA 62.00 vs 61.85, AIME 2024 70.40 vs 69.59 (no meaningful degradation).

**Best for:** Local math, science (GPQA), competitive-coding reasoning where a single 24 GB GPU runs a strong o1-mini-class dense model at Q4 with negligible loss.

**Sources:**
- https://huggingface.co/deepseek-ai/DeepSeek-R1-Distill-Qwen-32B
- https://arxiv.org/html/2501.12948v1
- https://ollama.com/library/deepseek-r1:32b
- https://artificialanalysis.ai/models/deepseek-r1-distill-qwen-32b
- https://arxiv.org/html/2505.02390v1
- https://llm-stats.com/models/deepseek-r1-distill-qwen-32b

---

## Qwen3-Coder-30B-A3B

**Ollama tag:** `qwen3-coder:30b`

Open-weight agentic coding model, Qwen Team (Alibaba), released Jul 31 2025. MoE 30.5B total / 3.3B active (128 experts, 8 active, 48 layers, GQA 32Q/4KV). Native 262,144 (256K) context, 1M via YaRN. Instruct-only, non-thinking, tuned for agentic coding, repo-scale understanding, tool/function calling. Qwen did NOT publish a full official table for this variant (GitHub issue #469).

| Benchmark | Score | Source |
| --- | --- | --- |
| SWE-bench Verified | 51.6 (OpenHands, 100 turns) | Qwen-reported, HF discussion #30 |
| Artificial Analysis Intelligence Index (v4.1) | 14 | Artificial Analysis |
| Aider Polyglot | ~62% (480B variant — NOT this 30B) (unverified) | Unsloth / Qwen blog |
| SWE-bench Multilingual | 67.2 (likely Qwen3-Coder-Next, not this) (unverified) | search aggregation |
| Terminal-Bench 2.0 | 51.5 (likely different/newer Qwen Coder) (unverified) | search aggregation |
| BFCL (tool use) | 76.63 (unverified; possibly conflated) | search aggregation |
| LiveCodeBench / HumanEval / MBPP / BigCodeBench / Spider / MMLU-Pro / GPQA / AIME / Arena-Hard / LMArena Elo | No model-specific published score found | — |

Caveat: numbers often attributed to "Qwen3 30B A3B" online (Arena-Hard 91.0, AIME 2024 80.4, LiveBench 74.3) belong to the general-purpose Qwen3-30B-A3B, a DIFFERENT model — do not attribute to the coder.

**Quant impact (q4):** No model-specific study. Q4_K_M (~17.7 GB) retains quality well; Unsloth UD-Q4_K_XL nearly matched bf16 on Aider for the 480B (60.9 vs 61.8). (Unverified for the 30B.)

**Best for:** Local agentic coding and tool-use needing long-context (256K–1M) repo understanding at low active-param (3B) inference cost.

**Sources:**
- https://huggingface.co/Qwen/Qwen3-Coder-30B-A3B-Instruct
- https://huggingface.co/Qwen/Qwen3-Coder-30B-A3B-Instruct/discussions/30
- https://github.com/QwenLM/Qwen3-Coder
- https://github.com/QwenLM/Qwen3-Coder/issues/469
- https://artificialanalysis.ai/models/qwen3-coder-30b-a3b-instruct
- https://unsloth.ai/docs/models/tutorials/qwen3-coder-how-to-run-locally

---

## Methodology & caveats

**How the data was gathered.** Each of the 13 models was researched independently (parallel per-model web research), drawing first on official sources — model cards, technical reports, and papers (e.g. Hugging Face cards, OpenAI/Google/Qwen/Z.ai cards, arXiv) — and then on reputable third-party leaderboards (Artificial Analysis, LMArena / Chatbot Arena, llm-stats, BenchLM, and others). Where a primary source reports a benchmark directly, it is cited as the source; aggregator-only or search-derived figures are flagged.

**Meaning of "(unverified)" / "(unv.)".** These flags mark any number that could not be confirmed against a primary source — typically figures from aggregators, secondary blogs, search snippets, or community evals, or values that may have been conflated with a different model size/variant. Treat them as indicative only. Several "Best for" notes and contextual figures (e.g. flagship-model reference numbers, 27B-dense Qwen3.6 figures) are included for orientation but are explicitly not the installed model's verified scores.

**Quant level affects real-world quality.** Every published score in this document reflects full-precision (BF16/FP8/MXFP4-native) weights. The user runs quantized GGUFs, shown by the suffix in each Ollama tag. As a rule of thumb: q8_0 and q5/q4_K_M lose little (often within ~1–3% of full precision, sometimes near-lossless for dense reasoning models at Q4_K_M), while an aggressive ~2-bit quant such as the Q2_K used for GLM-4.5-Air can lose meaningfully. Hard math, coding, and long-context tasks degrade first. Real-world output quality on the user's machine will therefore generally sit somewhat below the published numbers in the tables above.

**Apples-to-apples limits.** Benchmark suites evolve. Some 2026 models report AIME 2026, HMMT 2025/2026, LiveCodeBench v6, or SWE-bench Pro instead of (or alongside) the older AIME 2024/2025, MATH-500, and original SWE-bench Verified. The master comparison table notes the AIME year per cell and footnotes scaffold/effort/tool variations, but cross-generation comparisons should be made with care.
