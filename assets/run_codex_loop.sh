#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Usage:
  run_codex_loop.sh -p "PROMPT" [options]
  run_codex_loop.sh --prompt-file PROMPT.txt [options]
  run_codex_loop.sh

Options:
  -p, --prompt TEXT         Prompt used on every round.
      --prompt-file FILE    Read prompt from file.
      --sleep SECONDS       Sleep between rounds (default: ${DEFAULT_SLEEP_SECONDS}).
      --state-dir DIR       State/log dir (default: ${DEFAULT_STATE_DIR}).
      --project-root DIR    Project root shown to agent (default: ${DEFAULT_PROJECT_ROOT}).
      --original-prompt-file FILE
                            Persisted original user prompt snapshot.
                            Default: ${DEFAULT_ORIGINAL_PROMPT_FILE}
      --work-status-file FILE
                            Unified work-status / plan / todo / check file.
                            Default: ${DEFAULT_WORK_STATUS_FILE}
      --progress-file FILE  Progress file for agent to update each round.
                            Default: ${DEFAULT_PROGRESS_FILE}
      --plan-file FILE      Deprecated alias of --work-status-file.
      --todo-file FILE      Deprecated alias of --work-status-file.
      --new-thread          Start a fresh thread instead of resuming prior one.
      --allow-stale-work-status
                            Do not fail when work-status file is not updated this round.
      --allow-stale-plan    Deprecated alias of --allow-stale-work-status.
      --no-runtime-context  Do not append runtime context block to prompt.
  -h, --help                Show this help.

Behavior:
  - Runs forever by default; stop manually with Ctrl+C.
  - Runs with baked-in defaults when no arguments are provided.
  - Default sleep is 0 unless --sleep overrides it.
  - When prompt comes from a file, the file is re-read every round (hot reload).
  - First round uses: codex exec ...
  - Later rounds use: codex exec resume <thread_id> ...
  - Persists thread id, prompt snapshots, per-round events, messages, and history.
  - If no prompt is provided, defaults to ${DEFAULT_PROMPT_FILE}.
EOF
}

DEFAULT_PROJECT_ROOT="__CODEX_LOOP_DEFAULT_PROJECT_ROOT__"
DEFAULT_PROMPT_FILE="__CODEX_LOOP_DEFAULT_PROMPT_FILE__"
DEFAULT_STATE_DIR="__CODEX_LOOP_DEFAULT_STATE_DIR__"
DEFAULT_ORIGINAL_PROMPT_FILE="__CODEX_LOOP_DEFAULT_ORIGINAL_PROMPT_FILE__"
DEFAULT_WORK_STATUS_FILE="__CODEX_LOOP_DEFAULT_WORK_STATUS_FILE__"
DEFAULT_PROGRESS_FILE="__CODEX_LOOP_DEFAULT_PROGRESS_FILE__"
DEFAULT_SLEEP_SECONDS="__CODEX_LOOP_DEFAULT_SLEEP_SECONDS__"

PROMPT_TEXT=""
PROMPT_FILE=""
PROMPT_SOURCE=""
SLEEP_SECONDS="$DEFAULT_SLEEP_SECONDS"
STATE_DIR="$DEFAULT_STATE_DIR"
PROJECT_ROOT="$DEFAULT_PROJECT_ROOT"
ORIGINAL_PROMPT_FILE="$DEFAULT_ORIGINAL_PROMPT_FILE"
WORK_STATUS_FILE="$DEFAULT_WORK_STATUS_FILE"
PROGRESS_FILE="$DEFAULT_PROGRESS_FILE"
APPEND_RUNTIME_CONTEXT=1
REQUIRE_WORK_STATUS_UPDATE=1
CURRENT_EVENT_FILE=""
CURRENT_ROUND=""
FORCE_NEW_THREAD=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--prompt)
      PROMPT_TEXT="${2:-}"
      PROMPT_SOURCE="inline"
      shift 2
      ;;
    --prompt-file)
      PROMPT_FILE="${2:-}"
      PROMPT_SOURCE="file"
      shift 2
      ;;
    --sleep)
      SLEEP_SECONDS="${2:-}"
      shift 2
      ;;
    --state-dir)
      STATE_DIR="${2:-}"
      shift 2
      ;;
    --project-root)
      PROJECT_ROOT="${2:-}"
      shift 2
      ;;
    --original-prompt-file)
      ORIGINAL_PROMPT_FILE="${2:-}"
      shift 2
      ;;
    --work-status-file|--plan-file|--todo-file)
      WORK_STATUS_FILE="${2:-}"
      shift 2
      ;;
    --progress-file)
      PROGRESS_FILE="${2:-}"
      shift 2
      ;;
    --new-thread)
      FORCE_NEW_THREAD=1
      shift
      ;;
    --allow-stale-work-status|--allow-stale-plan)
      REQUIRE_WORK_STATUS_UPDATE=0
      shift
      ;;
    --no-runtime-context)
      APPEND_RUNTIME_CONTEXT=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "${PROMPT_SOURCE//[[:space:]]/}" ]]; then
  if [[ -f "$DEFAULT_PROMPT_FILE" ]]; then
    PROMPT_FILE="$DEFAULT_PROMPT_FILE"
    PROMPT_SOURCE="file"
  else
    echo "Prompt is required. Use -p or --prompt-file (or create $DEFAULT_PROMPT_FILE)." >&2
    exit 1
  fi
fi

if ! [[ "$SLEEP_SECONDS" =~ ^[0-9]+$ ]]; then
  echo "--sleep must be a non-negative integer." >&2
  exit 1
fi

if [[ -z "${ORIGINAL_PROMPT_FILE//[[:space:]]/}" ]]; then
  ORIGINAL_PROMPT_FILE="$STATE_DIR/original_user_prompt.md"
fi

if [[ -z "${WORK_STATUS_FILE//[[:space:]]/}" ]]; then
  WORK_STATUS_FILE="$STATE_DIR/work_status.md"
fi

if [[ -z "${PROGRESS_FILE//[[:space:]]/}" ]]; then
  PROGRESS_FILE="$STATE_DIR/progress.md"
fi

mkdir -p "$STATE_DIR"
mkdir -p "$STATE_DIR/legacy"
mkdir -p "$(dirname "$ORIGINAL_PROMPT_FILE")" "$(dirname "$WORK_STATUS_FILE")" "$(dirname "$PROGRESS_FILE")"

THREAD_FILE="$STATE_DIR/thread_id"
LAST_EVENTS_FILE="$STATE_DIR/last_events.jsonl"
LAST_MESSAGE_FILE="$STATE_DIR/last_message.txt"
HISTORY_FILE="$STATE_DIR/history.log"
PROMPTS_DIR="$STATE_DIR/prompts"
EVENTS_DIR="$STATE_DIR/events"
MESSAGES_DIR="$STATE_DIR/messages"
mkdir -p "$PROMPTS_DIR" "$EVENTS_DIR" "$MESSAGES_DIR"
touch "$HISTORY_FILE"

if [[ ! -f "$PROGRESS_FILE" ]]; then
  cat > "$PROGRESS_FILE" <<'EOF'
# Agent Progress

## Overall Verdict
- not started

## Completed
- none

## In Progress
- none

## Missing / Not Yet Verified
- none

## Key Metrics / Effects
- none

## Open Risks
- none

## Next Recommended Slice
- none
EOF
fi

if [[ ! -f "$ORIGINAL_PROMPT_FILE" ]]; then
  if [[ "$PROMPT_SOURCE" == "inline" ]]; then
    printf '%s\n' "$PROMPT_TEXT" > "$ORIGINAL_PROMPT_FILE"
  else
    cat "$PROMPT_FILE" > "$ORIGINAL_PROMPT_FILE"
  fi
fi

if [[ ! -f "$WORK_STATUS_FILE" ]]; then
  cat > "$WORK_STATUS_FILE" <<'EOF'
# Work Status

## Rules
- Each checklist item can be marked PASS only after the same check passes in two distinct rounds.
- Update this file at the end of every round.
- Re-interpret user intent every round using new evidence from this round.
- If previous plan or previous PASS conclusion is wrong, boldly reset/rewrite it and mark old result invalid.
- Organize each round around one primary, reasonably scoped, semantically coherent, and fully verifiable work package; the exact amount of code or number of subitems is up to model judgment. If several tightly coupled edits share one validation path or belong to the same functional slice, they should be completed together instead of being split into repeated tiny rounds with little forward progress.
- Evidence-backed recovery is valid progress: if current code/logs show some work is already finished, record it instead of pretending it still needs implementation.
- Use subagents to accelerate bounded exploration or disjoint implementation when helpful, but keep final integration, testing, perf checks, rollback decisions, and conclusions on the main agent.
- If a new error appears, stop scope expansion first; rollback or isolate unvalidated edits, restore the latest stable state, then continue.
- If rounds/logs become large, compress durable history directly into this file and archive/merge stale noisy logs under `legacy/` instead of replaying full history every round.

## Meta
- Last Updated (UTC):
- Current Round:
- Overall Status: in_progress

## Original Prompt Snapshot
- Source: original_user_prompt.md

## Bootstrap Recovery
- legacy_layout_detected:
- legacy_layout_rotated_to:
- bootstrap_subagents_used:
- recovered_existing_progress:
- recovered_evidence_paths:

## Durable History Summary
- Keep only long-lived conclusions that future rounds still need.
- Do not duplicate raw logs here; store evidence paths and short conclusions only.
- When this section grows too large, merge older items into batch summaries and move raw details to `legacy/`.

## Work Queue
- Keep one primary active `In Progress` item for tracking.
- Add new items with priority and evidence pointers.
- Move completed items to `Done` with command/log/commit traceability.

## In Progress
- [ ] Replace with the primary current active item

## Todo
- [ ] T001 Define concrete goal and acceptance tests (priority: high, deps: -, owner: codex)

## Blocked
- [ ] (include blocked_by: reason)

## Done
- [x] W000 Bootstrap work-status file

## Validation Matrix

| ID | Task | Status (todo/in_progress/blocked/done) | Implementation Status | Check Command | Round A Result | Round B Result | Pass Criteria | Final Check |
|----|------|------------------------------------------|-----------------------|---------------|----------------|----------------|---------------|-------------|
| P001 | Replace with first concrete item | todo | not started | <command> | pending | pending | same check passes in two distinct rounds | pending |

## Re-evaluation And Corrections (Required Every Round)
- Was any previous plan item wrong? If yes, rewrite and reset status:
- Was any previous PASS wrong after new evidence? If yes, set it back to FAIL/IN_PROGRESS and re-establish validation in later distinct rounds:
- Why this correction matches user intent better:

## Latest Round Update
- What changed:
- Risks / blockers:
- Next round first task:
EOF
fi

round_file() {
  local dir="$1"
  local round="$2"
  printf '%s/round-%04d%s' "$dir" "$round" "$3"
}

compute_next_round() {
  local max_round=0
  local f=""
  local base=""
  local num=""

  if [[ -d "$EVENTS_DIR" ]]; then
    while IFS= read -r f; do
      base="$(basename "$f")"
      num="${base#round-}"
      num="${num%.jsonl}"
      if [[ "$num" =~ ^[0-9]+$ ]]; then
        if (( 10#$num > max_round )); then
          max_round=$((10#$num))
        fi
      fi
    done < <(find "$EVENTS_DIR" -maxdepth 1 -type f -name 'round-*.jsonl' 2>/dev/null)
  fi

  echo $((max_round + 1))
}

handle_interrupt() {
  echo "Interrupted by user. Loop stopped." >&2

  if [[ -n "${CURRENT_EVENT_FILE//[[:space:]]/}" ]] && [[ -f "$CURRENT_EVENT_FILE" ]]; then
    local salvaged_thread=""
    salvaged_thread="$(jq -s -r 'map(select(.type=="thread.started") | .thread_id) | last // ""' "$CURRENT_EVENT_FILE" 2>/dev/null || true)"
    if [[ -n "$salvaged_thread" ]]; then
      printf '%s\n' "$salvaged_thread" > "$THREAD_FILE"
      echo "Saved thread_id from partial events: $salvaged_thread" >&2
    fi
  fi

  exit 130
}

build_prompt_for_round() {
  local round="$1"
  local out_file="$2"
  local runtime_block=""
  local original_prompt_text=""
  local work_status_text=""
  local current_prompt=""

  if [[ "$PROMPT_SOURCE" == "inline" ]]; then
    current_prompt="$PROMPT_TEXT"
  else
    if [[ ! -f "$PROMPT_FILE" ]]; then
      echo "Prompt file not found for round $round: $PROMPT_FILE" >&2
      return 1
    fi
    current_prompt="$(cat "$PROMPT_FILE")"
  fi

  printf '%s\n' "$current_prompt" > "$out_file"

  if (( APPEND_RUNTIME_CONTEXT == 1 )); then
    original_prompt_text="$(cat "$ORIGINAL_PROMPT_FILE")"
    work_status_text="$(cat "$WORK_STATUS_FILE")"
    runtime_block="$(cat <<EOF

================ RUNTIME CONTEXT ================
round: $round
project_root: $PROJECT_ROOT
state_dir: $STATE_DIR
history_log: $HISTORY_FILE
history_legacy_dir: $STATE_DIR/legacy
original_prompt_file: $ORIGINAL_PROMPT_FILE
work_status_file: $WORK_STATUS_FILE
progress_file: $PROGRESS_FILE

================ ORIGINAL USER PROMPT (MUST INCLUDE) ================
$original_prompt_text
======================================================================

================ PREVIOUS WORK STATUS (MUST INCLUDE) ==================
$work_status_text
======================================================================

Mandatory each round:
1) Re-scan current code and the logs above before changing anything.
2) Do not blindly trust earlier logs or prior conclusions; re-verify from code/tests.
3) Include original user prompt and previous work status in this round's reasoning.
4) Update progress_file with what is done, in-progress, and next actions.
5) Update work_status_file and keep one primary active item in "In Progress" for tracking; closely related work completed in the same round may be folded into it or moved directly to Done.
6) Keep the current plan, todo, validation status, and risks unified inside work_status_file.
7) Any checklist item is PASS only if the same test succeeds in two distinct rounds; do not complete both confirmations in one round.
8) At end of round, reflect new evidence + user intent; if old plan/check was wrong, boldly rewrite/reset it.
9) If a previous PASS is now suspicious or wrong, revoke it (set FAIL/IN_PROGRESS) and rebuild the proof in later distinct rounds.
10) Reply with concise: summary, changed files, test results, next step.
=================================================
EOF
)"
    printf '%s\n' "$runtime_block" >> "$out_file"
  fi
}

run_round() {
  local round="$1"
  local thread_id=""
  local ts=""
  local status=0
  local new_thread_id=""
  local last_message=""
  local plan_hash_before=""
  local plan_hash_after=""
  local plan_updated="no"
  local prompt_file=""
  local event_file=""
  local message_file=""
  local -a cmd=()

  prompt_file="$(round_file "$PROMPTS_DIR" "$round" ".prompt.txt")"
  event_file="$(round_file "$EVENTS_DIR" "$round" ".jsonl")"
  message_file="$(round_file "$MESSAGES_DIR" "$round" ".txt")"
  CURRENT_EVENT_FILE="$event_file"
  CURRENT_ROUND="$round"

  plan_hash_before="$(sha256sum "$WORK_STATUS_FILE" | awk '{print $1}')"

  build_prompt_for_round "$round" "$prompt_file"

  if [[ -s "$THREAD_FILE" ]] && (( FORCE_NEW_THREAD == 0 )); then
    thread_id="$(<"$THREAD_FILE")"
    cmd=(codex exec resume --json --skip-git-repo-check)
    cmd+=("$thread_id" -)
  else
    cmd=(codex exec --json --skip-git-repo-check)
    cmd+=(-)
  fi

  set +e
  "${cmd[@]}" < "$prompt_file" > "$event_file" 2>&1
  status=$?
  set -e

  cp "$event_file" "$LAST_EVENTS_FILE"

  if (( status != 0 )); then
    {
      echo "-----"
      echo "time_utc: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
      echo "round: $round"
      echo "status: failed($status)"
      echo "events_begin"
      cat "$event_file"
      echo "events_end"
    } >> "$HISTORY_FILE"
    echo "Round $round failed. Check $LAST_EVENTS_FILE" >&2
    exit "$status"
  fi

  new_thread_id="$(jq -s -r 'map(select(.type=="thread.started") | .thread_id) | last // ""' "$event_file")"
  if [[ -n "$new_thread_id" ]]; then
    thread_id="$new_thread_id"
    printf '%s\n' "$thread_id" > "$THREAD_FILE"
  elif [[ -s "$THREAD_FILE" ]]; then
    thread_id="$(<"$THREAD_FILE")"
  else
    echo "No thread_id found in events." >&2
    exit 1
  fi

  last_message="$(jq -s -r 'map(select(.type=="item.completed" and .item.type=="agent_message") | .item.text) | last // ""' "$event_file")"
  printf '%s\n' "$last_message" > "$LAST_MESSAGE_FILE"
  printf '%s\n' "$last_message" > "$message_file"

  plan_hash_after="$(sha256sum "$WORK_STATUS_FILE" | awk '{print $1}')"
  if [[ "$plan_hash_before" != "$plan_hash_after" ]]; then
    plan_updated="yes"
  fi

  if (( REQUIRE_WORK_STATUS_UPDATE == 1 )) && [[ "$plan_updated" != "yes" ]]; then
    {
      echo "-----"
      echo "time_utc: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
      echo "round: $round"
      echo "status: failed(work_status_not_updated)"
      echo "work_status_file: $WORK_STATUS_FILE"
      echo "hint: agent must update work_status_file every round"
    } >> "$HISTORY_FILE"
    echo "Round $round failed: work-status file not updated: $WORK_STATUS_FILE" >&2
    exit 2
  fi

  ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  {
    echo "-----"
    echo "time_utc: $ts"
    echo "round: $round"
    echo "thread_id: $thread_id"
    echo "plan_updated: $plan_updated"
    echo "message_begin"
    printf '%s\n' "$last_message"
    echo "message_end"
  } >> "$HISTORY_FILE"

  echo "[round $round] thread_id=$thread_id"
  echo "[round $round] prompt=$prompt_file"
  echo "[round $round] prompt_source=$PROMPT_SOURCE"
  if [[ "$PROMPT_SOURCE" == "file" ]]; then
    echo "[round $round] prompt_file_source=$PROMPT_FILE"
  fi
  echo "[round $round] events=$event_file"
  echo "[round $round] original_prompt_file=$ORIGINAL_PROMPT_FILE"
  echo "[round $round] work_status_file=$WORK_STATUS_FILE"
  echo "[round $round] plan_updated=$plan_updated"
  echo "[round $round] progress_file=$PROGRESS_FILE"
  printf '%s\n' "$last_message"
}

round="$(compute_next_round)"
if ! [[ "$round" =~ ^[0-9]+$ ]]; then
  round=1
fi
trap 'handle_interrupt' INT TERM
while true; do
  run_round "$round"

  round=$((round + 1))
  if (( SLEEP_SECONDS > 0 )); then
    sleep "$SLEEP_SECONDS"
  fi
done
