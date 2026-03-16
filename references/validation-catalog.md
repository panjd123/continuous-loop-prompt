# 验证目录

用这份目录把模糊的质量要求转换成可执行、可衡量的检查。

## Quick 模式（每轮）

每轮至少选一条命令。
每个检查项都要记录一条成功的验证命令，以及当前轮对应的具体证据。
一旦某条当前轮检查成功且证据已记录，即可标记 PASS。
不要为了流程形式而把同一条验证重复执行两次。
如果新证据推翻了之前的 PASS，必须立刻撤销，并基于最新证据重新建立验证结论。

1. Shell / 脚本项目
- `bash -n <script.sh>`
- `shellcheck <script.sh>`（若环境可用）
- `timeout 15 <smoke-command>`

2. Python 项目
- `python -m py_compile <key_file.py>`
- `python -m pytest -q <target_test>`
- `timeout 30 python <entrypoint> --help`

3. Node / TS 项目
- `npm run -s lint`
- `npm test -- --runInBand <target>`
- `node <entrypoint>.js --help`

4. C / C++ 项目
- `cmake --build . -j$(nproc)`
- `ctest --output-on-failure -R <target>`

## Full 模式（里程碑 / 收尾）

选择最贴近当前项目的检查，并保持命令可复现。

1. 正确性
- 变更模块的核心回归测试。
- 边界输入和异常路径测试。

2. 稳定性
- 只有在怀疑存在偶发失败，或稳定性本身就是交付目标时，才重复执行关键用例。
- 确认不存在间歇性失败。

3. 性能（若需要）
- 使用相同环境、相同输入、相同锁策略。
- 记录基线与当前结果。
- 显式报告退化阈值（例如：不差于 5%）。

## 阈值示例

在 prompt 中写一条明确、单行的阈值说明。

- 正确性：`所有选定测试必须通过（0 failures）`
- 数值：`max_abs <= 1e-5 且 max_rel <= 1e-4`
- 性能：`P50 延迟退化必须 <= 5%`
- 可靠性：`一次当前轮成功检查且带有具体证据即可标记 PASS；若后续出现反证，必须撤销`

## Work Status 记录规则

要求在 work-status 文件中为每个检查项保留这些字段：

- `check_command`
- `check_result`
- `evidence_path_or_metric`
- `final_check`（一次成功并记录证据后可设为 `PASS`，否则为 `FAIL` 或 `IN_PROGRESS`）

要求每轮都保留纠错字段：

- `intent_reassessment`
- `wrong_plan_fixed`
- `revoked_previous_pass`

如果循环是新建的，还应保留 bootstrap / 迁移字段：

- `legacy_layout_detected`
- `legacy_layout_rotated_to`
- `bootstrap_subagents_used`
- `recovered_existing_progress`
- `recovered_evidence_paths`

## 日志卫生

- 长输出统一重定向到文件。
- 只提炼摘要所需的关键行。
- 排障时优先扫描失败模式：
  - `rg -n "ERROR|Exception|Traceback|FAILED|timeout" <log_file>`
