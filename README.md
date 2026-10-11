# swegemma

Baseline and research work for the Google — Gemma 4 Developer Agent Competition (Kaggle)
and its Paper Track.

## Project layout

| Path | Purpose |
| :--- | :--- |
| `submission/` | **The deliverable.** Contents of this directory become `submission.zip` with `agent.yaml` at the archive root. Currently an adapter-free, single-agent baseline. |
| `submission/agent.yaml` | Root ADK agent config: model, tools, prompt include, sampling include. |
| `submission/eval_config.yaml` | Per-task budgets (time, tool calls, command timeout). |
| `submission/prompts/` | Markdown instructions loaded via `!include`. |
| `submission/configs/` | Sampling / generation parameters. |
| `experiments/` | Agent-config variants and run definitions for A/B comparisons. |
| `experiments/sample_submission_reference/` | **Unmodified copy of the official starter kit** (includes dummy zero-effect LoRAs and 1-min budget — reference only, do not submit). |
| `experiments/runs/` | Per-run experiment configs / manifests. |
| `scripts/` | Dev tooling: `package.sh` builds `submission.zip`. |
| `docs/` | Notes, harness findings, paper material. |
| `data/` | Local-only symlinks to downloaded assets (gitignored). `data/gemma-4-developer-agent` → the 129-task dataset. |
| `results/` | Evaluation outputs (gitignored): patches, traces, `task_results.jsonl`, `summary.json`. |

## Key facts

- Required model for submission: `gemma-4-31b-it-qat-w4a16-ct` (declared in `agent.yaml`; Kaggle serves it — do not download).
- Local proxy models (Ollama): `gemma4:e2b`, `gemma4:e4b`.
- Harness packages (`swegemma`, `adk-submission`, `adk-eval-core`, `google-adk`, `vllm`) come from the `metric/gemma-4-developer-agent-wheelhouse` Kaggle dataset — separate from the task data.
- Eval command once harness is installed:
  ```bash
  swegemma eval \
    --tasks data/gemma-4-developer-agent/tasks.jsonl \
    --snapshots-dir data/gemma-4-developer-agent/snapshots \
    --submission-dir submission \
    --results-dir results/run_01 \
    --sandbox docker \
    --task-id fastapi_15589
  ```
- Build the archive: `bash scripts/package.sh`
