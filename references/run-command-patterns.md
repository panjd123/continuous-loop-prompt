# Run Command Patterns

Always return exactly one runnable command.
The generated `run_codex_loop.sh` must already contain baked defaults for
prompt/state/original-prompt/work-status/progress/sleep, and it should live in
a **fresh worktree**. The final command should normally be a `cd` into that
fresh worktree followed by `./run_codex_loop.sh`.

## Preferred (fresh worktree already prepared)

```bash
cd /abs/path/to/fresh-worktree && ./run_codex_loop.sh
```

Use this when the skill has already:
- created a fresh worktree
- written the prompt under the canonical state dir
- installed the runner in that worktree

The runner must guarantee:
- runtime prompt includes original user prompt + previous work-status content
- each checklist item passes only after the same check succeeds in two distinct rounds
- work-status file is updated each round (default strict mode)
- end-of-round re-evaluation can rewrite/reset wrong prior plans and revoke wrong prior PASS
- default sleep is `0` unless the user explicitly requests a non-zero delay
- when prompt comes from a file, edits to that prompt file are picked up on the next round without restarting the loop

## Bootstrap Helper (during skill execution)

During skill execution, first use the bootstrap helper to create the fresh worktree
and install the runner:

```bash
bash /root/.codex/skills/continuous-loop-prompt/scripts/bootstrap_fresh_loop_worktree.sh \
  --source-repo .
```

After the skill has prepared the new worktree and written the prompt there, return
a simple:

```bash
cd /abs/path/to/fresh-worktree && ./run_codex_loop.sh
```

Do not return a pseudo command that depends on manual edits in the old source tree.

## Return Style

- Return command as plain code block.
- Ensure command is copy-run ready.
