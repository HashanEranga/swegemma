# Harness & dataset notes (verified by inspection, Oct 8–9 2026)

## Dataset (~/Documents/gemma-4-developer-agent, ~21 GiB)

- `tasks.jsonl` — 129 tasks: fastapi(67), rich(48), requests(13), httpx(1).
  Fields include `patch` (reference fix) and `test_patch` (hidden tests).
  **Never feed `patch`/`test_patch` to the agent** — evaluator-only.
- `snapshots/` — ~21 GiB of repo archives at `base_commit`.
- `graphs/` (403 MiB), `embeddings/` (447 MiB) — named by `<repo>_<base_commit>`,
  not always by `instance_id`. Verify harness filename resolution before
  relying on graph tools.
- `wheels/` — ~27 MiB of *task* deps (pytest, starlette, pydantic…).
  NOT the host harness packages.
- `docker/` — sandbox Dockerfiles (python:3.13-slim). `sandbox/setup.py` does
  offline editable install from `/wheels`.

## Harness behavior (HARNESS_README.md)

- Two containers: A (agent edits → `git diff` patch), B (fresh repo → apply
  patch → apply `test_patch` → pytest + JUnit XML → resolved bool).
- `submit_patch` is free and terminal — always call it last.
- `get_status` is free.
- `read_file` capped at 150 lines / 10k chars; `run_command` output 5k chars.
- `search_similar_code` resolves queries against **symbol names**, not
  natural language — pass function/class names.
- Test-file/config changes are forcibly reset before grading — editing tests
  is always useless.
- Scratch files left in `/workspace` become part of the patch — use `/tmp`.
- Context: 32,768 total on vLLM; ADK compaction threshold 14,336.
- Sample adapters (`main_lora`, `tool_lora`): rank-4 LoRA on layer 0 only;
  `lora_B` is all zeros → zero effect. Dummies to exercise adapter plumbing.
- Sample `eval_config` (1 min / 10 tool calls) is a smoke test, not a baseline.

## Model registry aliases accepted locally by the harness

gemma-4-31b-it-qat-w4a16-ct (required for Kaggle), gemma-4-31b-it, 27b,
26b-a4b, 12b, 9b, e4b, e2b (+`-it` suffixes). E2B/E4B aliases exist for
local CLI evals — submission must still declare the QAT checkpoint.

## Missing pieces locally

- Host wheelhouse: `kaggle datasets download metric/gemma-4-developer-agent-wheelhouse`
  (~880 MiB: swegemma 0.2.7, adk-submission 0.2.12, adk-eval-core 0.1.0,
  google-adk 1.36.1, vllm 0.19.1, transformers 5.13.1).
- Python ≥3.12 host env; Docker for sandboxes.
