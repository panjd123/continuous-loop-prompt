#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
用法：
  run_codex_loop.sh -p "PROMPT" [options]
  run_codex_loop.sh --prompt-file PROMPT.txt [options]
  run_codex_loop.sh

参数：
  -p, --prompt TEXT         每轮都使用这段提示词。
      --prompt-file FILE    从文件读取提示词。
      --sleep SECONDS       轮次之间的休眠时间（默认：${DEFAULT_SLEEP_SECONDS}）。
      --state-dir DIR       状态 / 日志目录（默认：${DEFAULT_STATE_DIR}）。
      --project-root DIR    展示给代理的项目根目录（默认：${DEFAULT_PROJECT_ROOT}）。
      --original-prompt-file FILE
                            持久化保存的原始用户提示词快照。
                            默认：${DEFAULT_ORIGINAL_PROMPT_FILE}
      --work-status-file FILE
                            统一的工作状态 / 计划 / todo / 检查文件。
                            默认：${DEFAULT_WORK_STATUS_FILE}
      --progress-file FILE  代理每轮更新的总体进展文件。
                            默认：${DEFAULT_PROGRESS_FILE}
      --plan-file FILE      --work-status-file 的废弃别名。
      --todo-file FILE      --work-status-file 的废弃别名。
      --new-thread          不沿用旧线程，直接启动新线程。
      --allow-stale-work-status
                            若本轮未更新 work-status 文件，不要直接失败。
      --allow-stale-plan    --allow-stale-work-status 的废弃别名。
      --no-runtime-context  不向提示词追加运行时上下文块。
  -h, --help                显示帮助。

行为：
  - 默认持续运行，需手动用 Ctrl+C 停止。
  - 若不传参数，则使用文件内置默认值运行。
  - 除非用 --sleep 覆盖，否则默认休眠时间为 0。
  - 若提示词来自文件，则每轮都会重新读取该文件（热加载）。
  - 第一轮使用：codex exec ...
  - 后续轮次使用：codex exec resume <thread_id> ...
  - 会持久化保存 thread id、提示词快照、每轮事件、消息和历史日志。
  - 若未显式提供提示词，则默认使用 ${DEFAULT_PROMPT_FILE}。
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
      echo "未知参数：$1" >&2
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
    echo "必须提供提示词。请使用 -p 或 --prompt-file（或创建 $DEFAULT_PROMPT_FILE）。" >&2
    exit 1
  fi
fi

if ! [[ "$SLEEP_SECONDS" =~ ^[0-9]+$ ]]; then
  echo "--sleep 必须是非负整数。" >&2
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

## 规则
- 这个文件是给用户看的，语言要直接、精炼。
- 不要把它写成逐轮流水账。
- 不要把篇幅浪费在已经完成的实现细节、临时排障笔记，或已经不再影响用户需求和下一步工作的短期状态上。
- 每 10 轮（10、20、30……）都要重写这个文件，把它压缩成围绕当前状态、剩余工作、用户可感知效果、开放风险和下一步建议的紧凑摘要。

## Overall Verdict
- 未开始

## Completed
- 无

## In Progress
- 无

## Missing / Not Yet Verified
- 无

## Key Metrics / Effects
- 无

## Open Risks
- 无

## Next Recommended Slice
- 无
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

## 规则
- 每个检查项在当前轮取得一次成功且有证据记录后即可标记 PASS。
- 每轮结束都要更新这个文件。
- 每轮都要根据本轮新证据重新理解用户意图。
- 如果旧计划或旧 PASS 结论被证明有误，就直接重写 / 重置，并让旧结果失效。
- 每轮都应围绕一个主要、范围合理、语义完整且可充分验证的工作包推进；具体改动量由模型自行判断。如果多个紧密耦合的改动共享同一验证路径，或天然属于同一功能切片，就应在同一轮一起完成，而不是拆成一串零碎小轮次。
- 基于证据恢复现状本身就是有效进展：如果当前代码 / 日志显示某些工作已经完成，应直接记录，而不是假装仍需实现。
- loop 启动 / bootstrap 时要记录当时的基线 commit（例如 `git rev-parse HEAD`）；后续维护、清理过期文件，或移除临时 debug 代码时，要优先与这个基线对照，并在结论里说明理由。
- 在合适的时候可以用 subagent 加速有边界的探索或互不重叠的实现切片；但最终集成、测试、性能检查、回滚判断和结论输出必须由主 agent 完成。
- 如果出现新错误，先停止继续扩大改动面；优先回退或隔离尚未验证的改动，恢复到最近稳定状态后再继续。
- 如果轮次 / 日志变多，应把持久历史直接压缩进这个文件，并把陈旧噪声日志归档到 `legacy/`，而不是每轮都重放全部历史。
- 每 10 轮（10、20、30……）都要把持久历史重写成围绕任务和当前状态的紧凑摘要，而不是保留逐轮日记；只保留仍然相关的状态、剩余工作、风险、决策和证据指针。

## Meta
- 最后更新时间（UTC）：
- 当前轮次：
- 整体状态：in_progress
- loop_start_commit：
- loop_start_commit_notes：

## Original Prompt Snapshot
- 来源：original_user_prompt.md

## Bootstrap Recovery
- legacy_layout_detected:
- legacy_layout_rotated_to:
- bootstrap_subagents_used:
- recovered_existing_progress:
- recovered_evidence_paths:

## Durable History Summary
- 这里只保留后续轮次仍需要的长期有效结论。
- 不要在这里重复粘贴原始日志；只保留证据路径和简短结论。
- 当这部分变长时，把更旧的内容合并成批次摘要，并把原始细节移入 `legacy/`。
- 若当前轮次是 10 的倍数，就按当前状态和剩余工作重写这里，而不是保留按时间排列的日记。

## Work Queue
- 始终只保留一个主要的 `In Progress` 项用于跟踪。
- 新任务加入时写明优先级和证据指针。
- 已完成项移入 `Done`，并保留命令 / 日志 / commit 的可追溯信息。

## In Progress
- [ ] 用当前主要进行中的事项替换这里

## Todo
- [ ] T001 明确具体目标和验收测试（priority: high, deps: -, owner: codex）

## Blocked
- [ ] （写明 blocked_by: reason）

## Done
- [x] W000 初始化 work-status 文件

## 验证矩阵

| ID | 任务 | 状态（todo/in_progress/blocked/done） | 实现状态 | 检查命令 | 检查结果 | 证据路径 / 指标 | 通过标准 | 最终结论 |
|----|------|------------------------------------------|----------|----------|----------|----------------|----------|----------|
| P001 | 用第一个具体事项替换这里 | todo | 未开始 | <command> | pending | <path or metric> | 当前轮一次成功且有证据记录即可通过 | pending |

## Re-evaluation And Corrections（每轮必填）
- 哪些旧计划项被证明有误？若有，如何重写并重置状态：
- 哪些旧 PASS 被新证据推翻？若有，如何改回 FAIL / IN_PROGRESS，并基于最新证据重建验证：
- 为什么这次纠错更贴近用户意图：
- 如果当前轮次是 10 的倍数，本轮如何重写旧历史以减少上下文污染，并只保留仍然相关的状态：

## Latest Round Update
- 本轮做了什么：
- 风险 / 阻塞：
- 下一轮首要任务：
EOF
fi

round_file() {
  local dir="$1"
  local round="$2"
  printf '%s/round-%04d%s' "$dir" "$round" "$3"
}

event_json_stream() {
  local src="$1"

  if [[ ! -f "$src" ]]; then
    return 1
  fi

  LC_ALL=C tr -d '\000' < "$src" | jq -cR 'fromjson? | select(type=="object")'
}

materialize_event_file() {
  local src="$1"
  local dst="$2"
  local tmp=""

  tmp="$(mktemp "${dst}.tmp.XXXXXX")"
  if ! event_json_stream "$src" > "$tmp"; then
    rm -f "$tmp"
    return 1
  fi

  mv "$tmp" "$dst"
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
  echo "收到用户中断信号，循环已停止。" >&2

  if [[ -n "${CURRENT_EVENT_FILE//[[:space:]]/}" ]] && [[ -f "$CURRENT_EVENT_FILE" ]]; then
    local salvaged_thread=""
    salvaged_thread="$(event_json_stream "$CURRENT_EVENT_FILE" | jq -s -r 'map(select(.type=="thread.started") | .thread_id) | last // ""' 2>/dev/null || true)"
    if [[ -n "$salvaged_thread" ]]; then
      printf '%s\n' "$salvaged_thread" > "$THREAD_FILE"
      echo "已从部分事件中恢复并保存 thread_id：$salvaged_thread" >&2
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
      echo "第 $round 轮未找到提示词文件：$PROMPT_FILE" >&2
      return 1
    fi
    current_prompt="$(cat "$PROMPT_FILE")"
  fi

  printf '%s\n' "$current_prompt" > "$out_file"

  if (( APPEND_RUNTIME_CONTEXT == 1 )); then
    original_prompt_text="$(cat "$ORIGINAL_PROMPT_FILE")"
    work_status_text="$(cat "$WORK_STATUS_FILE")"
    runtime_block="$(cat <<EOF

================ 运行时上下文 ================
轮次: $round
项目根目录: $PROJECT_ROOT
状态目录: $STATE_DIR
历史日志: $HISTORY_FILE
历史归档目录: $STATE_DIR/legacy
原始提示词文件: $ORIGINAL_PROMPT_FILE
工作状态文件: $WORK_STATUS_FILE
总体进展文件: $PROGRESS_FILE

================ 原始用户提示词（必须纳入本轮分析） ================
$original_prompt_text
======================================================================

================ 上一轮工作状态（必须纳入本轮分析） ==================
$work_status_text
======================================================================

每轮强制要求：
1) 任何改动前，先重新扫描当前代码和上述日志。
2) 不要盲信旧日志或旧结论；必须以当前代码 / 测试重新验证。
3) 本轮分析必须同时纳入原始用户提示词和上一轮工作状态。
4) 更新 progress_file 时必须用直接、精炼的语言写清：已完成、进行中、尚缺内容、关键效果、风险和下一步；不要保留已经不再重要的旧细节。
5) 更新 work_status_file，并始终只保留一个主要的 \`In Progress\` 项用于跟踪；同轮完成的紧密相关事项可以折叠进去，或直接移入 \`Done\`。
6) 当前计划、todo、验证状态和风险都必须统一维护在 work_status_file 中。
7) 任何检查项在当前轮一次成功且有证据记录后即可 PASS；不要为了形式重复执行同一验证。
8) 每轮结束时，都要结合新证据和用户意图重新审视计划；如果旧计划或旧检查结论有误，必须直接重写或重置。
9) 如果旧 PASS 现在变得可疑或错误，必须撤销（设为 FAIL / IN_PROGRESS），并基于最新证据重新建立验证。
10) 如果当前轮次是 10 的倍数，就把旧历史重写成围绕当前关键状态的简洁非时间线摘要，并把 progress_file 同步重写成同样精炼的用户摘要；不要继续堆叠逐轮细节。
11) 如果本轮要清理过期文件、临时产物或 debug 代码，先对照 work_status_file 中记录的 loop_start_commit，再说明这些内容为什么可以删除、归档或保留。
12) 回复必须简洁，至少包含：摘要、改动文件、测试结果、下一步。
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
  local raw_event_file=""
  local -a cmd=()

  prompt_file="$(round_file "$PROMPTS_DIR" "$round" ".prompt.txt")"
  event_file="$(round_file "$EVENTS_DIR" "$round" ".jsonl")"
  message_file="$(round_file "$MESSAGES_DIR" "$round" ".txt")"
  raw_event_file="$(mktemp "${TMPDIR:-/tmp}/codex-loop-round-${round}.raw.XXXXXX")"
  CURRENT_EVENT_FILE="$raw_event_file"
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
  "${cmd[@]}" < "$prompt_file" > "$raw_event_file" 2>&1
  status=$?
  set -e

  if ! materialize_event_file "$raw_event_file" "$event_file"; then
    echo "无法把原始事件流转换为 JSONL：$raw_event_file" >&2
    rm -f "$raw_event_file"
    exit 1
  fi

  cp "$event_file" "$LAST_EVENTS_FILE"
  rm -f "$raw_event_file"
  CURRENT_EVENT_FILE="$event_file"

  if (( status != 0 )); then
    {
      echo "-----"
      echo "时间(UTC): $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
      echo "轮次: $round"
      echo "状态: failed($status)"
      echo "事件开始"
      cat "$event_file"
      echo "事件结束"
    } >> "$HISTORY_FILE"
    echo "第 $round 轮失败，请检查 $LAST_EVENTS_FILE" >&2
    exit "$status"
  fi

  new_thread_id="$(jq -s -r 'map(select(.type=="thread.started") | .thread_id) | last // ""' "$event_file")"
  if [[ -n "$new_thread_id" ]]; then
    thread_id="$new_thread_id"
    printf '%s\n' "$thread_id" > "$THREAD_FILE"
  elif [[ -s "$THREAD_FILE" ]]; then
    thread_id="$(<"$THREAD_FILE")"
  else
    echo "未在事件中找到 thread_id。" >&2
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
      echo "时间(UTC): $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
      echo "轮次: $round"
      echo "状态: failed(work_status_not_updated)"
      echo "工作状态文件: $WORK_STATUS_FILE"
      echo "提示: agent 每轮都必须更新 work_status_file"
    } >> "$HISTORY_FILE"
    echo "第 $round 轮失败：work-status 文件未更新：$WORK_STATUS_FILE" >&2
    exit 2
  fi

  ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  {
    echo "-----"
    echo "时间(UTC): $ts"
    echo "轮次: $round"
    echo "thread_id: $thread_id"
    echo "工作状态是否更新: $plan_updated"
    echo "消息开始"
    printf '%s\n' "$last_message"
    echo "消息结束"
  } >> "$HISTORY_FILE"

  echo "[第 $round 轮] thread_id=$thread_id"
  echo "[第 $round 轮] prompt=$prompt_file"
  echo "[第 $round 轮] prompt_source=$PROMPT_SOURCE"
  if [[ "$PROMPT_SOURCE" == "file" ]]; then
    echo "[第 $round 轮] prompt_file_source=$PROMPT_FILE"
  fi
  echo "[第 $round 轮] events=$event_file"
  echo "[第 $round 轮] original_prompt_file=$ORIGINAL_PROMPT_FILE"
  echo "[第 $round 轮] work_status_file=$WORK_STATUS_FILE"
  echo "[第 $round 轮] plan_updated=$plan_updated"
  echo "[第 $round 轮] progress_file=$PROGRESS_FILE"
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
