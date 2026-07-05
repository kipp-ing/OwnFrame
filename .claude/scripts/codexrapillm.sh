#!/usr/bin/env bash
set -euo pipefail

# codexrapillm — dispatch a task brief to the local executor:
# codex exec --profile local → Qwen3.5-122B on the M3Ultra (rapid-mlx).
#
# Usage:
#   codexrapillm.sh [-s <sandbox>] [-e <effort>] [<brief-file>|-]
#     -s  sandbox: read-only | workspace-write (default) | danger-full-access
#     -e  model_reasoning_effort override for this dispatch (low|medium|high)
#     brief read from file argument, or stdin with "-" (default: stdin)
#
# Full codex output → ~/.codexrapillm/logs/<ts>.log (kept out of the repo so
# a running executor never sees orchestrator-created files in its tree).
# One TSV ledger row per dispatch → ~/.codexrapillm/ledger.tsv:
#   ts  sandbox  effort  exit  seconds  tokens  log  brief-head

SANDBOX="workspace-write"
EFFORT=""
while getopts "s:e:" opt; do
  case "$opt" in
    s) SANDBOX="$OPTARG" ;;
    e) EFFORT="$OPTARG" ;;
    *) exit 2 ;;
  esac
done
shift $((OPTIND - 1))

BRIEF_SRC="${1:--}"
if [ "$BRIEF_SRC" = "-" ]; then BRIEF="$(cat)"; else BRIEF="$(cat "$BRIEF_SRC")"; fi
[ -n "$BRIEF" ] || { echo "empty brief" >&2; exit 2; }

BASE="${CODEXRAPILLM_DIR:-$HOME/.codexrapillm}"
mkdir -p "$BASE/logs"
TS="$(date +%Y%m%d-%H%M%S)"
LOG="$BASE/logs/$TS.log"
LEDGER="$BASE/ledger.tsv"

ARGS=(exec --profile local -s "$SANDBOX")
[ -n "$EFFORT" ] && ARGS+=(-c "model_reasoning_effort=\"$EFFORT\"")

START=$(date +%s)
set +e
RAPID_MLX_API_KEY="$(cat "$HOME/.rapid-mlx-api-key")" \
  codex "${ARGS[@]}" "$BRIEF" </dev/null >"$LOG" 2>&1
EXIT=$?
set -e
SECONDS_TAKEN=$(( $(date +%s) - START ))

# codex exec prints "tokens used" followed by a formatted number (e.g. 40.548)
TOKENS="$(awk '/^tokens used$/{getline; gsub(/[^0-9]/,""); print; exit}' "$LOG")"
HEAD="$(printf '%s' "$BRIEF" | head -1 | cut -c1-80)"
printf '%s\t%s\t%s\t%s\t%ss\t%s\t%s\t%s\n' \
  "$TS" "$SANDBOX" "${EFFORT:-profile}" "$EXIT" "$SECONDS_TAKEN" "${TOKENS:-?}" "$LOG" "$HEAD" >> "$LEDGER"

# Surface the executor's final message (codex exec repeats it after the token
# line); fall back to the raw tail on abnormal exits.
echo "--- codexrapillm: exit=$EXIT ${SECONDS_TAKEN}s tokens=${TOKENS:-?} log=$LOG ---"
awk '/^tokens used$/{found=NR} {line[NR]=$0} END{if(found) for(i=found+2;i<=NR;i++) print line[i]}' "$LOG" \
  | sed '/^$/d' | tail -40
[ "$EXIT" -eq 0 ] || tail -5 "$LOG"
exit "$EXIT"
