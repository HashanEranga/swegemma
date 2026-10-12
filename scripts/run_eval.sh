#!/usr/bin/env bash
# Run a swegemma eval and record a self-contained manifest under
# experiments/runs/<run_id>/ (manifest.yaml + submission snapshot).
# The manifest is generated at run time — never edit it by hand.
#
# Usage:
#   bash scripts/run_eval.sh <run_id> [options] [-- <extra swegemma eval args>]
#
# Options:
#   --task-id <id>          Task to run (repeatable). Omit = all tasks.
#   --submission-dir <dir>  Submission variant dir (default: submission)
#   --tasks <file>          tasks.jsonl path
#                           (default: data/gemma-4-developer-agent/tasks.jsonl)
#   --snapshots-dir <dir>   snapshots dir
#                           (default: data/gemma-4-developer-agent/snapshots)
#   --sandbox <mode>        sandbox mode (default: docker)
#   --models-yaml <path>    Model registry override; "off" for harness default
#                           (default: auto = models.local.yaml if present)
#   --force                 Overwrite an existing run with the same id
#   -h, --help              Show this help
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

RUN_ID=""
SUBMISSION_DIR="submission"
TASKS_JSONL="data/gemma-4-developer-agent/tasks.jsonl"
SNAPSHOTS_DIR="data/gemma-4-developer-agent/snapshots"
SANDBOX="docker"
MODELS_YAML="auto"
FORCE=0
TASK_IDS=()
EXTRA_ARGS=()

usage() { sed -n '2,20p' "$0"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-id)        TASK_IDS+=("$2"); shift 2 ;;
    --submission-dir) SUBMISSION_DIR="$2"; shift 2 ;;
    --tasks)          TASKS_JSONL="$2"; shift 2 ;;
    --snapshots-dir)  SNAPSHOTS_DIR="$2"; shift 2 ;;
    --sandbox)        SANDBOX="$2"; shift 2 ;;
    --models-yaml)    MODELS_YAML="$2"; shift 2 ;;
    --force)          FORCE=1; shift ;;
    -h|--help)        usage; exit 0 ;;
    --)               shift; EXTRA_ARGS+=("$@"); break ;;
    -*)               echo "Unknown option: $1" >&2; usage; exit 2 ;;
    *)
      if [[ -z "$RUN_ID" ]]; then RUN_ID="$1"; shift
      else echo "Unexpected argument: $1" >&2; usage; exit 2; fi ;;
  esac
done

if [[ -z "$RUN_ID" || "$RUN_ID" =~ [/[:space:]] ]]; then
  echo "Usage: bash scripts/run_eval.sh <run_id> [--task-id <id> ...]" >&2
  exit 2
fi
[[ -d "$SUBMISSION_DIR" ]] || { echo "No such submission dir: $SUBMISSION_DIR" >&2; exit 1; }

RUN_DIR="$ROOT/experiments/runs/$RUN_ID"
RES_DIR="$ROOT/results/$RUN_ID"

if [[ -e "$RUN_DIR" || -e "$RES_DIR" ]]; then
  if [[ "$FORCE" -eq 1 ]]; then
    rm -rf "$RUN_DIR" "$RES_DIR"
  else
    echo "Run '$RUN_ID' already exists ($RUN_DIR / $RES_DIR). Use --force to overwrite." >&2
    exit 1
  fi
fi

mkdir -p "$RUN_DIR/submission" "$RES_DIR"

# Resolve models yaml: "auto" = models.local.yaml if present, "off" = none
if [[ "$MODELS_YAML" == "auto" ]]; then
  if [[ -f models.local.yaml ]]; then MODELS_YAML="models.local.yaml"; else MODELS_YAML=""; fi
elif [[ "$MODELS_YAML" == "off" ]]; then
  MODELS_YAML=""
elif [[ ! -f "$MODELS_YAML" ]]; then
  echo "No such models yaml: $MODELS_YAML" >&2; exit 1
fi

# --- Snapshot provenance (captured BEFORE the run so it survives failures) ---
cp -a "$SUBMISSION_DIR/." "$RUN_DIR/submission/"
[[ -n "$MODELS_YAML" ]] && cp -a "$MODELS_YAML" "$RUN_DIR/models.yaml"

SUB_SHA="$(cd "$SUBMISSION_DIR" && find . -type f -print0 | sort -z \
  | xargs -0 sha256sum | sha256sum | cut -d' ' -f1)"
GIT_SHA="$(git -C "$ROOT" rev-parse --short=12 HEAD 2>/dev/null || echo unknown)"
if [[ -n "$(git -C "$ROOT" status --porcelain 2>/dev/null)" ]]; then
  GIT_DIRTY=true
else
  GIT_DIRTY=false
fi
MODEL_DECLARED="$(grep -m1 '^model:' "$SUBMISSION_DIR/agent.yaml" | awk '{print $2}')"

CMD=(swegemma eval
  --tasks "$TASKS_JSONL"
  --snapshots-dir "$SNAPSHOTS_DIR"
  --submission-dir "$SUBMISSION_DIR"
  --results-dir "$RES_DIR"
  --sandbox "$SANDBOX")
if [[ -n "$MODELS_YAML" ]]; then CMD+=(--models-yaml "$MODELS_YAML"); fi
if [[ ${#TASK_IDS[@]} -gt 0 ]]; then
  for tid in "${TASK_IDS[@]}"; do CMD+=(--task-id "$tid"); done
fi

# Budgets: swegemma eval ignores eval_config.yaml on the local CLI — map it
# to the equivalent flags. Passthrough args (after --) can still override.
EVAL_CFG="$SUBMISSION_DIR/eval_config.yaml"
_yaml_val() { grep -E "^[[:space:]]*$1:" "$EVAL_CFG" 2>/dev/null | head -1 | awk '{print $2}'; }
EVAL_LINES=()
if [[ -f "$EVAL_CFG" ]]; then
  for pair in "timeout_seconds:--timeout-seconds" "max_tool_calls:--max-tool-calls" \
              "max_time_minutes:--max-time-minutes" "max_turns:--max-turns"; do
    key="${pair%%:*}"; flag="${pair##*:}"
    val="$(_yaml_val "$key")"
    if [[ -n "$val" ]]; then
      CMD+=("$flag" "$val")
      EVAL_LINES+=("  $key: $val")
    fi
  done
fi
if [[ ${#EXTRA_ARGS[@]} -gt 0 ]]; then CMD+=("${EXTRA_ARGS[@]}"); fi
CMD_STR="$(printf '%q ' "${CMD[@]}")"

{
  echo "run_id: $RUN_ID"
  echo "created_at: $(date -Iseconds)"
  echo "git:"
  echo "  commit: $GIT_SHA"
  echo "  dirty: $GIT_DIRTY"
  echo "submission_dir: $SUBMISSION_DIR"
  echo "submission_sha256: $SUB_SHA"
  echo "model:"
  echo "  declared: ${MODEL_DECLARED:-unknown}"
  if [[ -n "$MODELS_YAML" ]]; then
    echo "  local_override: $MODELS_YAML"
  fi
  echo "sandbox: $SANDBOX"
  echo "evaluation:"
  if [[ ${#EVAL_LINES[@]} -gt 0 ]]; then
    printf '%s\n' "${EVAL_LINES[@]}"
  else
    echo "  source: harness defaults (no eval_config.yaml found)"
  fi
  echo "tasks:"
  if [[ ${#TASK_IDS[@]} -gt 0 ]]; then
    for tid in "${TASK_IDS[@]}"; do echo "  - $tid"; done
  else
    echo "  - all"
  fi
  echo "results_dir: results/$RUN_ID"
  echo "command: $CMD_STR"
  echo "status: running"
} > "$RUN_DIR/manifest.yaml"

echo "Manifest: $RUN_DIR/manifest.yaml"
echo "Running:  $CMD_STR"

# --- Run ---
SECONDS=0
set +e
"${CMD[@]}"
rc=$?
set -e
DUR=$SECONDS

# --- Append outcome (a manifest still showing "running" = eval died mid-run) ---
sed -i 's/^status: running$/status: finished/' "$RUN_DIR/manifest.yaml"
{
  echo "outcome:"
  echo "  finished_at: $(date -Iseconds)"
  echo "  duration_seconds: $DUR"
  echo "  eval_exit_code: $rc"
  if [[ -f "$RES_DIR/summary.json" && $rc -eq 0 ]]; then
    echo "  status: completed"
    python3 - "$RES_DIR/summary.json" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))
print(f"  total_tasks: {s.get('total_tasks')}")
print(f"  resolved: {s.get('resolved')}")
print(f"  resolution_rate: {s.get('resolution_rate')}")
print(f"  errors: {s.get('errors')}")
PY
  else
    echo "  status: failed"
  fi
} >> "$RUN_DIR/manifest.yaml"

echo
echo "Done. Manifest: $RUN_DIR/manifest.yaml"
echo "Results:      $RES_DIR"
[[ -f "$RES_DIR/summary.json" ]] && cat "$RES_DIR/summary.json"
exit "$rc"
