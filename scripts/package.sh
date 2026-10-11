#!/usr/bin/env bash
# Build submission.zip with agent.yaml at the archive root.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/submission.zip"

rm -f "$OUT"
(cd "$ROOT/submission" && zip -r "$OUT" .)
echo "Wrote $OUT"
unzip -l "$OUT" | head -20
