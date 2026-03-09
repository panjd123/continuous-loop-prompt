# Validation Catalog

Use this catalog to convert vague quality asks into measurable checks.

## Quick Mode (per round)

Pick at least one command per round.
For each checklist item, run the same validation command across at least two distinct rounds and record Round A / Round B.
Mark PASS only when both round-separated checks succeed.
Do not complete both confirmations inside a single round.
If new evidence contradicts a previous PASS result, revoke it immediately and rebuild validation across two later distinct rounds.

1. Shell / Script projects
- `bash -n <script.sh>`
- `shellcheck <script.sh>` (if available)
- `timeout 15 <smoke-command>`

2. Python projects
- `python -m py_compile <key_file.py>`
- `python -m pytest -q <target_test>`
- `timeout 30 python <entrypoint> --help`

3. Node/TS projects
- `npm run -s lint`
- `npm test -- --runInBand <target>`
- `node <entrypoint>.js --help`

4. C/C++ projects
- `cmake --build . -j$(nproc)`
- `ctest --output-on-failure -R <target>`

## Full Mode (milestone / pre-finish)

Pick the closest fit and keep commands reproducible.

1. Correctness
- Core regression suite for changed modules.
- Edge-case tests for boundary inputs and error paths.

2. Stability
- Re-run the same key case in at least 2 distinct rounds.
- Confirm no intermittent failure.

3. Performance (if required)
- Same environment, same input, same lock policy.
- Record baseline vs current.
- Report regression threshold explicitly (example: no worse than 5%).

## Threshold Examples

Use one concrete line in prompt.

- Correctness: "All selected tests must pass (0 failures)."
- Numerical: "max_abs <= 1e-5 and max_rel <= 1e-4."
- Performance: "P50 latency regression must be <= 5%."
- Reliability: "The same check must succeed in two distinct rounds."

## Work Status Recording Rule

Require per-item verification fields in the work-status file:

- `check_command`
- `round_a_result`
- `round_b_result`
- `final_check` (only `PASS` when both round-separated checks pass; otherwise `FAIL` or `IN_PROGRESS`)

Require round-level correction fields:

- `intent_reassessment`
- `wrong_plan_fixed`
- `revoked_previous_pass`

Require bootstrap / migration fields when a loop is newly created:

- `legacy_layout_detected`
- `legacy_layout_rotated_to`
- `bootstrap_subagents_used`
- `recovered_existing_progress`
- `recovered_evidence_paths`

## Log Hygiene

- Redirect long outputs to file.
- Extract only key lines for summary.
- Use pattern scan for failures:
  - `rg -n "ERROR|Exception|Traceback|FAILED|timeout" <log_file>`
