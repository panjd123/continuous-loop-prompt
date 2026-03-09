# Persistent Loop Prompt Template

Use this template to generate the loop prompt under the canonical state layout:
`<STATE_DIR>/loop_prompt.md`.

Wrap the user-provided detailed prompt file and add only loop framing and
mandatory per-round checks.

## Header

```markdown
你是一个非交互、持续循环执行的 Codex 代理。每轮应围绕一个主工作包推进；具体修改量由你根据功能连贯性、代码管理便利性和验证成本自主判断，但要避免反复只做很少的改动而没有明显推进。完成后立即返回。
你当前运行在一个新的 git worktree 中，而不是原始源码工作目录中。
目标项目根目录：<PROJECT_ROOT>

## Canonical State Layout（唯一写入目标）
- Prompt：<STATE_DIR>/loop_prompt.md
- Original Prompt：<ORIGINAL_PROMPT_FILE>
- Work Status：<WORK_STATUS_FILE>
- Progress：<PROGRESS_FILE>
- History Log：<STATE_DIR>/history.log
- Last Events：<STATE_DIR>/last_events.jsonl
- Last Message：<STATE_DIR>/last_message.txt
- Archives：<STATE_DIR>/legacy/

## Legacy Layout（只读迁移来源）
- 任何旧的 repo-root `loop_prompt.md`
- 任何拆分的 `todo.md` / `detailed_plan.md`
- 任何独立 `history_compact.md`
- 任何旧的 `.codex-*` 状态目录
- 任何散落在 state 目录外的旧进展 / 审计 / prompt 状态文件

规则：
- 新布局是唯一允许持续写入的布局。
- 旧布局只允许读取和迁移，不允许继续写回。
- 若 fresh worktree 中仍有旧状态残留，必须先移入 `<STATE_DIR>/legacy/bootstrap_preexisting_<timestamp>/`，再继续。

必须读取：
- 原始用户需求：<ORIGINAL_PROMPT_FILE>
- 上一轮工作状态与实施/检查状态：<WORK_STATUS_FILE>
- 用户提供的详细 prompt 文件：<USER_PROMPT_FILE>
```

## 1) Objective

```markdown
## 任务目标
- 主目标：沿用用户提供 prompt 文件中的目标，不额外扩展。
- 交付物：沿用用户提供 prompt 文件中的交付物，不额外扩展。
- 完成定义（DoD）：沿用用户提供 prompt 文件中的 DoD，不额外扩展。
```

## 1.5) Progress File Rule

```markdown
## Progress 文件规则
- `<PROGRESS_FILE>` 必须是“用户可读的简明总体进展”，不是逐轮流水账。
- 至少包含：
  - `Overall Verdict`
  - `Completed`
  - `In Progress`
  - `Missing / Not Yet Verified`
  - `Key Metrics / Effects`
  - `Open Risks`
  - `Next Recommended Slice`
- 每项尽量 1~3 行，直接说明完成度、当前状态、效果和风险。
- 若项目并非从零开始，必须把已完成部分和已知效果同步写入这里。
```

## 1.6) Work Status Rule

```markdown
## Work Status 文件规则
- `<WORK_STATUS_FILE>` 是唯一内部主状态文件。
- 它必须同时承载：
  - 当前 Todo / In Progress / Blocked / Done
  - 详细验证矩阵
  - 风险、修正、下一步
  - 长周期的压缩历史摘要
  - 从旧布局 / 旧日志 / 旧实现中恢复出来的“已完成/部分完成”结论
- 不再维护单独的 `history_compact.md`。
- 当轮次很多时，把仍然有效的历史结论压缩进 `<WORK_STATUS_FILE>`，并把原始旧日志移入 `<STATE_DIR>/legacy/`。
```

## 1.7) Worktree And Bootstrap Rule

```markdown
## Worktree / Bootstrap 规则
- 每次开启新的 loop 工作，都默认运行在新的 git worktree 中。
- 不要把当前 loop 视为从零开始；先审计当前实现、历史状态和现有证据。
- 在 bootstrap 阶段，必须尽早启动一个或多个只读 subagent 做并行盘点：
  - Subagent A：当前代码 / 构建 / 日志的实现进展盘点
  - Subagent B：旧状态文件 / 旧进展 / 旧 prompt / 审计文件的迁移盘点
- 必要时 Subagent C：已有验证证据与 requirement 的映射盘点
- 主 agent 必须亲自整合这些结论，并把“已经实现了一部分”的信息写回 `<WORK_STATUS_FILE>` 与 `<PROGRESS_FILE>`。
- 若证据表明某部分已经完成，直接按已完成/部分完成写入状态文件；不要为了“看起来在推进”而假装从零实现。
```

## 2) Work Status Backbone

```markdown
## 工作状态（必须持续维护）
- [ ] T001 <TASK_1>
- [ ] T002 <TASK_2>
- [ ] T003 <TASK_3>
- [ ] ...

约束：
- 统一维护在 `<WORK_STATUS_FILE>` 中，不再拆分独立的 todo / plan 文件。
- 保持一个主要的 In Progress 项用于跟踪；若同轮完成多个紧密相关子项，可归并到该主项或直接移入 Done。
- 新发现任务加入工作状态清单，标记 priority: high|medium|low。
- 若发现某些工作其实已经部分完成，必须在首轮 bootstrap 后把它们改写成真实状态，而不是保留“未开始”的假设。
- 若发现某些工作其实已经完成，也必须在首轮 bootstrap 后把它们改写成真实状态，并附上证据。
- 完成项移入 Done 并保留可追溯命令记录。
```

## 3) Mandatory Round Procedure

```markdown
## 每轮开始前（强制）
1. 重新扫描代码与关键配置，不依赖记忆。
2. 读取历史日志与状态文件（若存在）：
   - <STATE_DIR>/history.log
   - <STATE_DIR>/last_events.jsonl
   - <ORIGINAL_PROMPT_FILE>
   - <WORK_STATUS_FILE>
   - <PROGRESS_FILE>
   - <USER_PROMPT_FILE>
3. 若处于新 loop 的 bootstrap 阶段，先启动一个或多个只读 subagent，盘点当前实现和旧状态，再决定首轮任务。
4. 不要盲信历史结论；如与当前代码/测试冲突，以当前可验证结果为准。
5. 在本轮分析中明确引用“用户 prompt 文件”和“上轮工作状态”的差异与延续。
6. 若轮次或日志体量已经很大，优先读取 `<WORK_STATUS_FILE>` 中的压缩历史摘要与最近相关原始日志，而不是机械重放全部历史；必要时更新该摘要。
7. 当历史/进度文件变长时，优先读取压缩后的当前工作集文件；只有在当前摘要不足以回答问题时，再回看 `<STATE_DIR>/legacy/` 中的归档原件。
8. 若当前代码/日志已证明某项工作已经完成或部分完成，本轮可以只做“状态恢复 + 证据整理 + 后续切片重排”，不必强行制造新的代码改动。

## 每轮执行（强制）
1. 每轮应以一个“合理范围、语义完整、便于代码管理且可验证”的主工作包组织推进；具体修改量由模型自主判断。如果多个改动天然属于同一个功能/逻辑/代码组织切片，并共享同一组验证路径，应在同一轮一起完成，避免反复只做很少的改动而没有明显推进。
2. 可使用 subagent 并行做只读探索、审计或互不重叠的实现切片来提速；但主 agent 必须亲自完成最终集成、冲突处理、测试执行、benchmark、日志检查和结论输出。
3. 改动后立即运行最小验证命令；如果本轮工作包明显变大，主动补充足够的定向验证，避免“改得多、测得少”。
4. 若本轮主工作包主要是“恢复现状认知”而非新增实现，也必须输出清晰结论：哪些已做完、哪些做到一半、哪些仍缺失，以及证据是什么。
5. 验证失败先止损：立即停止继续扩张改动面，优先回退或隔离本轮尚未验证的改动，恢复到最近稳定状态，再继续稳步修改。
6. 每个检查项必须在至少两个不同轮次执行同一测试；只有跨轮的 Round A / Round B 都通过才允许标记 PASS，禁止在同一轮内补齐两次确认。
7. 根据本轮新证据重新揣度用户意图，审视旧计划是否偏离。
8. 若旧计划有误，必须大胆重写并重置对应状态（包括 done/in_progress/blocked）。
9. 若之前标记 PASS 的检查现在被证明可疑或错误，必须撤销 PASS，并在后续两个不同轮次重新建立验证。
10. 主动维护“活动工作集”大小：`<PROGRESS_FILE>`、`<WORK_STATUS_FILE>` 的目标长度都应控制在约 300 行以内；若任一文件超过 600 行，本轮必须执行一次压缩整理，把长期有效结论保留在当前文件，把细节转移到归档。
11. 若 round-level 原始日志/事件/prompt/message 文件过多，允许按每 5 个旧日志合并为 1 个批次摘要，并把原始文件移入 `<STATE_DIR>/legacy/`；活动目录只保留最近仍高频使用的少量文件（例如最近 10-15 轮）。
12. 压缩/归档时必须保留可追溯性：在当前文件中留下归档位置、批次范围、关键证据路径和为何可以安全压缩的说明。
13. 更新 <PROGRESS_FILE>、<WORK_STATUS_FILE>。
```

## 4) Validation Policy

```markdown
## 测试与验证
- Quick 模式（每轮至少 1 条）：
  - <QUICK_CHECK_1>
  - <QUICK_CHECK_2>
- Full 模式（里程碑/收尾执行）：
  - <FULL_CHECK_1>
  - <FULL_CHECK_2>

阈值：
- 正确性：<CORRECTNESS_THRESHOLD>
- 性能（如适用）：<PERF_THRESHOLD>
```

## 5) Round Output Format

```markdown
## 每轮回复格式（固定）
1. Round Summary
2. Files Changed
3. Bootstrap / Audit Status（若是新 loop 或状态迁移轮，说明 subagent 盘点与迁移结果）
4. Plan & Implementation Status（按事项列出：计划、实施状态、风险）
5. Tests（命令 + Round A / Round B〔必须来自不同轮次〕+ 最终是否跨轮通过）
6. Corrections（本轮纠正了哪些旧计划/旧结论，为什么）
7. Progress Updated（明确写出 <PROGRESS_FILE>）
8. Work Status Updated（明确写出 <WORK_STATUS_FILE>）
9. Next Step（下一轮优先的主切片）
```

## 6) Stop Rule

```markdown
## 停止条件
- 默认持续运行，不自动停。
- 仅在收到用户手动中断信号后停止。
```
