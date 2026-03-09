---
name: continuous-loop-prompt
description: >-
  Turn a user-provided detailed prompt file into a production-ready persistent
  Codex loop package in a fresh git worktree: inspect current implementation
  progress and legacy state, normalize everything into the new canonical state
  layout, then output one command that starts the loop immediately.
---

# Continuous Loop Prompt

## Overview

Generate a loop-ready prompt and launch command from a detailed prompt file.
Do this in a **fresh git worktree**, not in the current source tree, and make the
generated loop use the **new canonical state layout** from the first round.

## Canonical Layout

The new layout is authoritative and must be described from its own perspective:

- `<state-dir>/loop_prompt.md`
- `<state-dir>/original_user_prompt.md`
- `<state-dir>/work_status.md`
- `<state-dir>/progress.md`
- `<state-dir>/history.log`
- `<state-dir>/last_events.jsonl`
- `<state-dir>/last_message.txt`
- `<state-dir>/prompts/`
- `<state-dir>/events/`
- `<state-dir>/messages/`
- `<state-dir>/legacy/`

Older split layouts are **legacy inputs only**. Examples:

- repo-root `loop_prompt.md`
- split `todo.md` + `detailed_plan.md`
- standalone `history_compact.md`
- prior `.codex-*` state directories
- progress files outside the state directory

If legacy state artifacts are present in the fresh worktree, rotate them into
`<state-dir>/legacy/bootstrap_preexisting_<timestamp>/` before using the new
layout. Do not continue writing into the old layout.

## Workflow

1. Treat the user-provided prompt file as authoritative.
- Do not reinterpret or expand the request into new objectives.
- Do not add new deliverables or acceptance criteria beyond the provided file.

2. Create a fresh worktree before writing the loop package.
- Every new loop engagement must run in a new git worktree directory.
- Do not reuse the source repo working directory as the loop directory.
- Use the bundled helper:
  - `/root/.codex/skills/continuous-loop-prompt/scripts/bootstrap_fresh_loop_worktree.sh`
- The helper must:
  - create a fresh worktree
  - install the runner there
  - normalize defaults to the canonical state layout
  - rotate any pre-existing state residue into `legacy/`

3. Bootstrap context with subagents before drafting the prompt.
- Spawn one or more **read-only** subagents early.
- At minimum cover these two inventories in parallel:
  - current implementation progress from code / build targets / logs
  - legacy state / progress / prompt / audit files that may already capture partial completion
- If helpful, spawn a third read-only subagent for validation / evidence mapping.
- Do not assume the project starts from zero.
- If the repo already has partially completed work, explicitly carry that into the new
  `work_status.md` and `progress.md`.
- If the repo already fully satisfies part of the requested work, record that with
  evidence instead of pretending it is still todo.
- Treat prior notes as hints, not truth; prefer current code and fresh command outputs.

4. Draft the persistent loop prompt.
- Start from [prompt-template.md](references/prompt-template.md).
- Wrap the user-provided prompt file content, adding only:
  - non-interactive loop header
  - canonical state-layout rules
  - legacy-layout migration rules
  - bootstrap subagent requirement
  - mandatory per-round file reads/checks
  - concise round output format requirements
- If the prompt file does not specify explicit paths, set defaults under `<state-dir>`:
  - prompt: `<state-dir>/loop_prompt.md`
  - original prompt: `<state-dir>/original_user_prompt.md`
  - progress: `<state-dir>/progress.md`
  - work status: `<state-dir>/work_status.md`
  - history archive: `<state-dir>/legacy/`
- Require `progress.md` to stay user-facing and concise: overall status,
  completed / in-progress / missing work, key effects or metrics, open risks,
  and next recommended slice. Do not let it turn into a round-by-round log.
- Require `work_status.md` to include both:
  - current execution state
  - durable compressed history / recovered prior progress
- Make it explicit that evidence-backed state recovery is valid progress: the agent
  does not need to force unnecessary code edits merely to appear active.
- Require each round input to include both original user prompt and previous
  work-status / implementation / check status.
- Require end-of-round re-evaluation: if old plan is wrong, rewrite/reset it.
- Require validation rollback: if previously PASS is now suspicious/wrong, revoke it.
- Keep one primary `In Progress` item for tracking at any time; closely related subitems may still be completed in the same round and then folded into that item or moved directly to `Done`.
- Require the first bootstrap round to use subagents when the loop is freshly created
  or when `work_status.md` does not yet contain a reliable recovered baseline.
- The generated `run_codex_loop.sh` must embed all default runtime paths directly in
  the file so it can be launched as `./run_codex_loop.sh`.
- Unless the user explicitly requests otherwise, bake `sleep=0` into the runner.
- The runner must hot-reload the prompt file every round when the prompt comes from
  `--prompt-file` or the baked default prompt path.
- The prompt should explicitly tell the agent to organize each round around one
  primary, reasonably scoped, semantically coherent, and fully verifiable work
  package, while leaving the exact amount of code / subitems to model judgment.
  Closely related work that improves coherence or avoids repeated tiny rounds
  should be completed together when practical. Still require immediate
  rollback/isolation when errors appear.
- The prompt should explicitly discourage fake churn: if a round's best outcome is
  recovering already-finished progress into the new state files or proving that a
  requested slice is already done, that is acceptable and should be recorded cleanly.
- The prompt should require long-running loops to compress durable history directly
  into `work_status.md` and archive stale raw logs under `legacy/`.
- The prompt should explicitly cap active working-set files at about 300 lines where
  practical (`progress`, `work_status`); if either exceeds roughly 600 lines, the
  agent should compress it that round.

5. Define measurable validation.
- If the user prompt file already defines validation, keep it as-is.
- Otherwise, use [validation-catalog.md](references/validation-catalog.md) to add sufficient targeted checks.
- Ensure each loop round includes at least one executable verification command.
- Enforce: each checklist item can be marked PASS only after the same check passes in two distinct rounds.
- Enforce: old PASS is not sticky; new evidence can downgrade PASS to FAIL/IN_PROGRESS.
- Enforce: if the loop accumulates many rounds, the agent must summarize durable history into
  `<state-dir>/work_status.md` and rely on that plus recent relevant raw logs.
- Enforce: current progress/summary files should not grow unbounded; require periodic compaction and archive pointers.

6. Produce runnable outputs.
- Prepare the fresh worktree during skill execution.
- Write the final prompt file inside the new state directory:
  - `<state-dir>/loop_prompt.md`
- Install the runner in the fresh worktree root:
  - `<worktree>/run_codex_loop.sh`
- Follow [run-command-patterns.md](references/run-command-patterns.md).
- Ensure the generated runner file includes baked defaults for:
  - prompt
  - state
  - original prompt
  - work status
  - progress
  - sleep
- Prefer returning:
  - `cd <fresh-worktree> && ./run_codex_loop.sh`
- Ensure the prompt tells the agent to compact/archive stale logs when rounds grow large,
  while preserving key evidence pointers.

## Reference Loading

Load only the needed reference file:

- Use [prompt-template.md](references/prompt-template.md) to wrap the provided prompt file.
- Use [validation-catalog.md](references/validation-catalog.md) to choose measurable checks.
- Use [run-command-patterns.md](references/run-command-patterns.md) to format the final command.
- Use bundled scripts when needed:
  - `/root/.codex/skills/continuous-loop-prompt/scripts/bootstrap_fresh_loop_worktree.sh`
  - `/root/.codex/skills/continuous-loop-prompt/scripts/install_runner.sh`

## Output Contract

Return these items every time:

1. `Worktree Dir`
- Absolute path to the fresh worktree used for this loop package.

2. `Prompt File`
- Absolute path to the generated prompt file inside the state directory.

3. `Runnable Command`
- One shell command only, directly executable, non-interactive, starts the loop immediately.
- Prefer `cd <fresh-worktree> && ./run_codex_loop.sh`.
- The command should rely on defaults baked into `run_codex_loop.sh`, not on a long runtime flag list.

4. `Validation Plan`
- Quick mode checks (per round).
- Full mode checks (milestone or pre-finish).
- Pass/fail thresholds.
- Explicit cross-round validation rule per checklist item (Round A / Round B in different rounds).
- Explicit rollback rule when prior validation is contradicted by new evidence.

5. `Assumptions And Risks`
- Explicit unknowns and how the prompt mitigates them.
- Explicit note on any legacy layout detected and how it was rotated / archived.

## Quality Gates

Before finalizing:

1. Confirm fresh-worktree isolation.
- The loop package is created in a fresh git worktree directory.
- The returned command starts from that fresh worktree, not from the source repo tree.

2. Confirm layout migration is explicit.
- The prompt distinguishes the new canonical layout from older legacy layouts.
- Legacy state artifacts are treated as read-only inputs and rotated to `legacy/` if present.
- The prompt writes only to the new canonical layout.

3. Confirm bootstrap inventory is explicit.
- The prompt requires one or more read-only subagents at loop bootstrap.
- The prompt explicitly warns that the implementation may already be partially complete.
- The prompt requires recovered progress to be written into `work_status.md` and `progress.md`.

4. Confirm prompt includes all mandatory sections.
- Goal, canonical layout, legacy-layout handling, worktree rules, bootstrap inventory,
  work-status structure, per-round procedure, test policy, update rules, stop criteria.

5. Confirm anti-hallucination behavior is explicit.
- Require re-scan and re-validation each round.
- Forbid blind trust in previous logs/messages.
- Require explicit carry-over of original prompt + previous work-status/check status.
- Require explicit correction section for wrong prior plans and wrong prior PASS conclusions.

6. Confirm command-path consistency.
- Prompt path exists inside the state directory.
- Runner exists in the fresh worktree root.
- Runner file already contains baked defaults for prompt/state/original-prompt/work-status/progress/sleep.
- Runner hot-reloads the prompt file on each round when using a prompt file source.
- State/original-prompt/work-status/progress paths exist or are auto-created by runner.

7. Confirm reproducibility.
- Command can be copy-run directly.
- The fresh worktree path is explicit.
