#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
用法：
  install_runner.sh [options]

参数：
      --target DIR   目标项目目录（默认：当前目录）。
      --output FILE  输出脚本路径（默认：<target>/run_codex_loop.sh）。
      --project-root DIR
                     生成 runner 时写入的默认项目根目录。
                     默认：--target 的绝对路径。
      --default-prompt-file FILE
                     写入的默认 prompt 文件。默认：<state-dir>/loop_prompt.md
      --default-state-dir DIR
                     写入的默认状态目录。默认：<project-root>/.codex-loop-state
      --default-original-prompt-file FILE
                     写入的原始 prompt 文件。默认：<state-dir>/original_user_prompt.md
      --default-work-status-file FILE
                     写入的统一 work-status 文件。默认：<state-dir>/work_status.md
      --default-progress-file FILE
                     写入的 progress 文件。默认：<state-dir>/progress.md
      --default-sleep SECONDS
                     写入的默认休眠间隔。默认：0
  -f, --force        覆盖已有输出文件。
  -h, --help         显示帮助。
EOF
}

TARGET_DIR="$(pwd)"
OUTPUT_FILE=""
FORCE=0
PROJECT_ROOT=""
DEFAULT_PROMPT_FILE=""
DEFAULT_STATE_DIR=""
DEFAULT_ORIGINAL_PROMPT_FILE=""
DEFAULT_WORK_STATUS_FILE=""
DEFAULT_PROGRESS_FILE=""
DEFAULT_SLEEP_SECONDS="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      TARGET_DIR="${2:-}"
      shift 2
      ;;
    --output)
      OUTPUT_FILE="${2:-}"
      shift 2
      ;;
    --project-root)
      PROJECT_ROOT="${2:-}"
      shift 2
      ;;
    --default-prompt-file)
      DEFAULT_PROMPT_FILE="${2:-}"
      shift 2
      ;;
    --default-state-dir)
      DEFAULT_STATE_DIR="${2:-}"
      shift 2
      ;;
    --default-original-prompt-file)
      DEFAULT_ORIGINAL_PROMPT_FILE="${2:-}"
      shift 2
      ;;
    --default-work-status-file)
      DEFAULT_WORK_STATUS_FILE="${2:-}"
      shift 2
      ;;
    --default-progress-file)
      DEFAULT_PROGRESS_FILE="${2:-}"
      shift 2
      ;;
    --default-sleep)
      DEFAULT_SLEEP_SECONDS="${2:-}"
      shift 2
      ;;
    -f|--force)
      FORCE=1
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

if [[ -z "${OUTPUT_FILE//[[:space:]]/}" ]]; then
  OUTPUT_FILE="$TARGET_DIR/run_codex_loop.sh"
fi

TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"

if [[ -z "${PROJECT_ROOT//[[:space:]]/}" ]]; then
  PROJECT_ROOT="$TARGET_DIR"
else
  PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"
fi

if [[ -z "${DEFAULT_STATE_DIR//[[:space:]]/}" ]]; then
  DEFAULT_STATE_DIR="$PROJECT_ROOT/.codex-loop-state"
fi

if [[ -z "${DEFAULT_PROMPT_FILE//[[:space:]]/}" ]]; then
  DEFAULT_PROMPT_FILE="$DEFAULT_STATE_DIR/loop_prompt.md"
fi

if [[ -z "${DEFAULT_ORIGINAL_PROMPT_FILE//[[:space:]]/}" ]]; then
  DEFAULT_ORIGINAL_PROMPT_FILE="$DEFAULT_STATE_DIR/original_user_prompt.md"
fi

if [[ -z "${DEFAULT_WORK_STATUS_FILE//[[:space:]]/}" ]]; then
  DEFAULT_WORK_STATUS_FILE="$DEFAULT_STATE_DIR/work_status.md"
fi

if [[ -z "${DEFAULT_PROGRESS_FILE//[[:space:]]/}" ]]; then
  DEFAULT_PROGRESS_FILE="$DEFAULT_STATE_DIR/progress.md"
fi

if ! [[ "$DEFAULT_SLEEP_SECONDS" =~ ^[0-9]+$ ]]; then
  echo "--default-sleep 必须是非负整数。" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE_FILE="$SKILL_DIR/assets/run_codex_loop.sh"

if [[ ! -f "$SOURCE_FILE" ]]; then
  echo "未找到 runner 模板：$SOURCE_FILE" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT_FILE")"

if [[ -e "$OUTPUT_FILE" && "$FORCE" -ne 1 ]]; then
  echo "输出文件已存在：$OUTPUT_FILE（可使用 --force 覆盖）" >&2
  exit 1
fi

cp "$SOURCE_FILE" "$OUTPUT_FILE"

escape_sed() {
  printf '%s' "$1" | sed -e 's/[\\/&]/\\&/g'
}

sed -i \
  -e "s/__CODEX_LOOP_DEFAULT_PROJECT_ROOT__/$(escape_sed "$PROJECT_ROOT")/g" \
  -e "s/__CODEX_LOOP_DEFAULT_PROMPT_FILE__/$(escape_sed "$DEFAULT_PROMPT_FILE")/g" \
  -e "s/__CODEX_LOOP_DEFAULT_STATE_DIR__/$(escape_sed "$DEFAULT_STATE_DIR")/g" \
  -e "s/__CODEX_LOOP_DEFAULT_ORIGINAL_PROMPT_FILE__/$(escape_sed "$DEFAULT_ORIGINAL_PROMPT_FILE")/g" \
  -e "s/__CODEX_LOOP_DEFAULT_WORK_STATUS_FILE__/$(escape_sed "$DEFAULT_WORK_STATUS_FILE")/g" \
  -e "s/__CODEX_LOOP_DEFAULT_PROGRESS_FILE__/$(escape_sed "$DEFAULT_PROGRESS_FILE")/g" \
  -e "s/__CODEX_LOOP_DEFAULT_SLEEP_SECONDS__/$(escape_sed "$DEFAULT_SLEEP_SECONDS")/g" \
  "$OUTPUT_FILE"

chmod +x "$OUTPUT_FILE"

echo "已安装 runner：$OUTPUT_FILE"
