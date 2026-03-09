#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  bootstrap_fresh_loop_worktree.sh [options]

Options:
      --source-repo DIR     Source repo / existing worktree to branch from (default: current directory).
      --worktree-dir DIR    Explicit fresh worktree directory. Default: sibling timestamped directory.
      --branch NAME         Branch name for the new worktree. Default: codex-loop-<timestamp>.
      --state-dir-name DIR  State dir name inside the new worktree. Default: .codex-loop-state
      --runner-output FILE  Runner output path inside the new worktree. Default: <worktree>/run_codex_loop.sh
      --force               If target directory already exists, rename it to *.legacy.<timestamp>.
  -h, --help               Show help.
EOF
}

SOURCE_REPO="$(pwd)"
WORKTREE_DIR=""
BRANCH_NAME=""
STATE_DIR_NAME=".codex-loop-state"
RUNNER_OUTPUT=""
FORCE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-repo)
      SOURCE_REPO="${2:-}"
      shift 2
      ;;
    --worktree-dir)
      WORKTREE_DIR="${2:-}"
      shift 2
      ;;
    --branch)
      BRANCH_NAME="${2:-}"
      shift 2
      ;;
    --state-dir-name)
      STATE_DIR_NAME="${2:-}"
      shift 2
      ;;
    --runner-output)
      RUNNER_OUTPUT="${2:-}"
      shift 2
      ;;
    --force)
      FORCE=1
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

SOURCE_REPO="$(cd "$SOURCE_REPO" && pwd)"
REPO_ROOT="$(git -C "$SOURCE_REPO" rev-parse --show-toplevel)"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"

if [[ -z "${WORKTREE_DIR//[[:space:]]/}" ]]; then
  WORKTREE_DIR="${REPO_ROOT}-codex-loop-${TIMESTAMP}"
fi
WORKTREE_DIR="$(python - <<'PY' "$WORKTREE_DIR"
import os, sys
print(os.path.abspath(sys.argv[1]))
PY
)"

if [[ -z "${BRANCH_NAME//[[:space:]]/}" ]]; then
  BRANCH_NAME="codex-loop-${TIMESTAMP}"
fi

if [[ -z "${RUNNER_OUTPUT//[[:space:]]/}" ]]; then
  RUNNER_OUTPUT="$WORKTREE_DIR/run_codex_loop.sh"
fi

if [[ -e "$WORKTREE_DIR" ]]; then
  if git -C "$REPO_ROOT" worktree list --porcelain | rg -Fqx "worktree $WORKTREE_DIR"; then
    echo "Target directory is already a registered git worktree: $WORKTREE_DIR" >&2
    echo "Choose a new worktree path instead of rotating it in place." >&2
    exit 1
  fi
  if [[ "$FORCE" -ne 1 ]]; then
    echo "Target worktree dir already exists: $WORKTREE_DIR (use --force to rotate it aside)" >&2
    exit 1
  fi
  mv "$WORKTREE_DIR" "${WORKTREE_DIR}.legacy.${TIMESTAMP}"
fi

git -C "$REPO_ROOT" worktree add -b "$BRANCH_NAME" "$WORKTREE_DIR" HEAD >/dev/null

STATE_DIR="$WORKTREE_DIR/$STATE_DIR_NAME"
ROTATE_STAGING="$WORKTREE_DIR/.codex-loop-bootstrap-staging-${TIMESTAMP}"
mkdir -p "$ROTATE_STAGING"

rotate_if_present() {
  local rel="$1"
  if [[ -e "$WORKTREE_DIR/$rel" ]]; then
    mkdir -p "$ROTATE_STAGING/$(dirname "$rel")"
    mv "$WORKTREE_DIR/$rel" "$ROTATE_STAGING/$rel"
  fi
}

rotate_if_present ".codex-loop-state"
rotate_if_present ".codex-spec-rebuild-state"
rotate_if_present "loop_prompt.md"
rotate_if_present "run_codex_loop.sh"
rotate_if_present "todo.md"
rotate_if_present "detailed_plan.md"
rotate_if_present "progress.md"
rotate_if_present "history_compact.md"

mkdir -p "$STATE_DIR/legacy"
LEGACY_BUCKET="$STATE_DIR/legacy/bootstrap_preexisting_${TIMESTAMP}"
mkdir -p "$LEGACY_BUCKET"

if [[ -d "$ROTATE_STAGING" ]] && find "$ROTATE_STAGING" -mindepth 1 -print -quit | grep -q .; then
  while IFS= read -r path; do
    rel="${path#"$ROTATE_STAGING"/}"
    mkdir -p "$LEGACY_BUCKET/$(dirname "$rel")"
    mv "$path" "$LEGACY_BUCKET/$rel"
  done < <(find "$ROTATE_STAGING" -mindepth 1 -maxdepth 1)
fi

rmdir "$ROTATE_STAGING" 2>/dev/null || true

bash /root/.codex/skills/continuous-loop-prompt/scripts/install_runner.sh \
  --target "$WORKTREE_DIR" \
  --output "$RUNNER_OUTPUT" \
  --project-root "$WORKTREE_DIR" \
  --default-prompt-file "$STATE_DIR/loop_prompt.md" \
  --default-state-dir "$STATE_DIR" \
  --default-original-prompt-file "$STATE_DIR/original_user_prompt.md" \
  --default-work-status-file "$STATE_DIR/work_status.md" \
  --default-progress-file "$STATE_DIR/progress.md" \
  --default-sleep 0 \
  --force >/dev/null

cat <<EOF
WORKTREE_DIR=$WORKTREE_DIR
BRANCH_NAME=$BRANCH_NAME
STATE_DIR=$STATE_DIR
PROMPT_FILE=$STATE_DIR/loop_prompt.md
ORIGINAL_PROMPT_FILE=$STATE_DIR/original_user_prompt.md
WORK_STATUS_FILE=$STATE_DIR/work_status.md
PROGRESS_FILE=$STATE_DIR/progress.md
RUNNER_OUTPUT=$RUNNER_OUTPUT
LEGACY_BUCKET=$LEGACY_BUCKET
EOF
