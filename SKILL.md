---
name: continuous-loop-prompt
description: >-
  把用户提供的详细提示词文件转换为可直接运行的持久 Codex 循环包：在全新的
  git worktree 中盘点当前实现进度和旧状态，统一迁移到新的规范状态目录，并输出
  一条可立即启动循环的命令。
---

# 持续循环 Prompt

## 概览

把一份详细提示词文件整理成可直接启动的 loop prompt 和运行命令。
必须在**全新的 git worktree**中完成，而不是直接在当前源码目录里操作；并且从首轮开始就使用**新的规范状态布局**。

## 规范状态布局

新的布局是唯一权威布局，必须按它自己的视角来描述：

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

旧的分散式布局只作为**只读迁移输入**。例如：

- repo 根目录下的 `loop_prompt.md`
- 拆分的 `todo.md` + `detailed_plan.md`
- 独立的 `history_compact.md`
- 旧的 `.codex-*` 状态目录
- 位于状态目录之外的进展文件

如果 fresh worktree 中已经存在旧状态产物，必须先把它们转移到
`<state-dir>/legacy/bootstrap_preexisting_<timestamp>/`，再开始使用新布局。
不要继续往旧布局写内容。

## 工作流程

1. 把用户提供的提示词文件视为权威输入。
- 不要擅自重解释或扩展成新的目标。
- 不要在文件之外新增交付物或验收标准。

2. 在写 loop 包之前先创建新的 worktree。
- 每一次新的循环任务都必须运行在新的 git worktree 目录中。
- 不要复用源仓库当前工作目录作为循环目录。
- 使用内置脚本：
  - `/root/.codex/skills/continuous-loop-prompt/scripts/bootstrap_fresh_loop_worktree.sh`
- 该脚本必须：
  - 创建新的 worktree
  - 在其中安装 runner
  - 把默认路径统一到规范状态布局
  - 把已有状态残留转移到 `legacy/`

3. 在起草 prompt 之前先用 subagent 做 bootstrap 盘点。
- 尽早启动一个或多个**只读** subagent。
- 至少并行覆盖这两类盘点：
  - 从代码 / 构建目标 / 日志中盘点当前实现进度
  - 从旧状态 / 旧进展 / 旧 prompt / 审计文件中盘点已有工作
- 必要时可增加第三个只读 subagent，用于验证证据和需求的映射。
- 不要假设项目从零开始。
- 如果仓库里已经有部分工作完成，必须把这些内容明确写入新的
  `work_status.md` 和 `progress.md`。
- 如果仓库已经完全满足部分需求，应记录证据，而不是假装它仍然待做。
- 旧笔记只能作为线索，不能直接当事实；优先相信当前代码和最新命令输出。

4. 起草持久循环 prompt。
- 以 [prompt-template.md](references/prompt-template.md) 为基础。
- 包装用户提供的提示词文件，只补充以下内容：
  - 非交互循环头部
  - 规范状态布局规则
  - 旧布局迁移规则
  - bootstrap subagent 要求
  - 每轮强制读取 / 检查规则
  - 简洁的每轮输出格式要求
- 如果提示词文件没有明确路径，就默认放在 `<state-dir>` 下：
  - prompt：`<state-dir>/loop_prompt.md`
  - 原始提示词：`<state-dir>/original_user_prompt.md`
  - progress：`<state-dir>/progress.md`
  - work status：`<state-dir>/work_status.md`
  - 历史归档：`<state-dir>/legacy/`
- prompt 必须显式区分“agent 常规可写状态文件”和“runner 管理只读文件”：
  - 常规可写：`work_status.md`、`progress.md`
  - runner 管理只读：`history.log`、`last_events.jsonl`、`last_message.txt`、`prompts/`、`events/`、`messages/`、`original_user_prompt.md`
- prompt 必须明确禁止代理手动编辑 `events/round-*.jsonl` 或其他 runner 生成的 event/message 文件，避免与 runner 的实时写入冲突。
- 要求 `progress.md` 保持面向用户且简洁：包含总体状态、已完成 / 进行中 / 尚缺工作、关键效果或指标、开放风险、下一步建议切片。不要把它写成逐轮流水账。
- 要求 `progress.md` 使用直接、压缩的语言：不要把篇幅浪费在已经完成的实现细节、临时排障笔记，或已不再影响用户目标和下一步工作的内容上。
- 要求 `work_status.md` 同时包含：
  - 当前执行状态
  - 持久压缩历史 / 恢复出的旧进度
- prompt 必须明确要求代理在 loop 启动 / bootstrap 时记录当时的基线 commit（例如 `git rev-parse HEAD` 写入 `work_status.md`）；后续维护、清理过期文件，或移除临时 debug 代码时，要优先与这个基线对照，判断哪些是本循环期间引入或应该回收的内容。
- 明确指出：基于证据恢复状态本身就是有效进展，代理不需要为了“看起来在工作”而强行制造代码改动。
- 要求每轮输入都包含原始用户提示词以及上一轮 work status / 实现 / 检查状态。
- 要求每轮结束都重新审视计划：如果旧计划不对，就直接重写或重置。
- 要求校验可回滚：如果先前的 PASS 现在变得可疑或错误，必须撤销。
- 任一时刻只保留一个主要 `In Progress` 项；同轮完成的紧密相关子项可以折叠进去，或直接移入 `Done`。
- 如果循环是新建的，或者 `work_status.md` 还没有可靠的恢复基线，则首轮 bootstrap 必须使用 subagent。
- 生成的 `run_codex_loop.sh` 必须把默认运行路径直接写入文件，使其可通过 `./run_codex_loop.sh` 直接启动。
- 除非用户明确要求，否则 runner 内置 `sleep=0`。
- 当 prompt 来源于 `--prompt-file` 或内置默认 prompt 路径时，runner 必须在每轮热加载该文件。
- prompt 必须明确要求代理以一个主要、范围合理、语义完整、可充分验证的工作包来组织每一轮，同时允许模型自行判断这一轮应包含多少代码或多少相关子项。
- 紧密相关、共享验证路径、一起完成更连贯的改动，应尽量在同一轮做完，避免无意义的小步重复。
- prompt 必须明确反对“假推进”：如果某一轮最好的结果只是把已完成工作恢复到状态文件里，或者证明某个切片其实已经完成，这仍然是可接受结果，应被干净地记录下来。
- prompt 必须要求长周期循环把持久历史直接压缩进 `work_status.md`，并把陈旧原始日志归档到 `legacy/`。
- prompt 必须明确要求每 10 轮做一次高质量历史刷新（10、20、30……）：停止继续按轮次堆叠笔记，把历史改写为以任务和当前决策为中心的压缩状态，只保留当前仍重要的内容，把已解决区域收敛为简短结论和证据指针。
- 对 `progress.md` 也应用同样的每 10 轮压缩规则：改写成更直接的用户摘要，只保留仍与用户需求、当前效果、风险和下一步相关的内容，丢弃不会继续影响工作的旧细节。
- prompt 必须明确限制活动工作集文件大小：`progress.md` 和 `work_status.md` 目标都应控制在约 300 行内；若任一文件超过约 600 行，该轮必须压缩。

5. 定义可衡量的验证要求。
- 如果用户提示词文件已经定义了验证方式，就沿用。
- 否则，使用 [validation-catalog.md](references/validation-catalog.md) 补充足够的定向检查。
- 确保每轮至少包含一条可执行的验证命令。
- 强制规则：每个检查项在当前轮取得一次成功且记录证据后即可标记 PASS。
- 强制规则：PASS 不是永久有效；后续新证据可以把 PASS 降级为 FAIL 或 IN_PROGRESS。
- 强制规则：如果轮次很多，代理必须把持久历史压缩进 `<state-dir>/work_status.md`，并优先依赖它和最近相关原始日志。
- 强制规则：至少每 10 轮，代理必须把陈旧历史重写为围绕当前状态、剩余工作、持久决策和证据指针的非时间线摘要，而不是保留逐轮回顾。
- 强制规则：至少每 10 轮，代理还必须把 `progress.md` 重写成更紧的用户摘要，避免继续详细描述已完成或临时性的工作。
- 强制规则：当前的进展 / 摘要文件不能无限增长，必须定期压缩并留下归档指针。

6. 产出可直接运行的结果。
- 在技能执行过程中准备好 fresh worktree。
- 最终 prompt 文件写入新的状态目录：
  - `<state-dir>/loop_prompt.md`
- runner 安装到 fresh worktree 根目录：
  - `<worktree>/run_codex_loop.sh`
- 遵循 [run-command-patterns.md](references/run-command-patterns.md)。
- 确保生成出的 runner 已内置以下默认值：
  - prompt
  - state
  - original prompt
  - work status
  - progress
  - sleep
- 优先返回：
  - `cd <fresh-worktree> && ./run_codex_loop.sh`
- 确保 prompt 明确要求：当轮次和日志变大时，要压缩 / 归档陈旧日志，同时保留关键证据指针。

## 参考文件

只按需加载必要的参考文件：

- 用 [prompt-template.md](references/prompt-template.md) 包装用户提供的提示词文件。
- 用 [validation-catalog.md](references/validation-catalog.md) 选择可衡量的检查方案。
- 用 [run-command-patterns.md](references/run-command-patterns.md) 组织最终命令格式。
- 需要时使用内置脚本：
  - `/root/.codex/skills/continuous-loop-prompt/scripts/bootstrap_fresh_loop_worktree.sh`
  - `/root/.codex/skills/continuous-loop-prompt/scripts/install_runner.sh`

## 输出约定

每次都返回以下内容：

1. `Worktree Dir`
- fresh worktree 的绝对路径。

2. `Prompt File`
- 状态目录内生成的 prompt 文件绝对路径。

3. `Runnable Command`
- 只返回一条 shell 命令，必须可直接执行、非交互、能立即启动循环。
- 优先使用 `cd <fresh-worktree> && ./run_codex_loop.sh`。
- 命令应依赖 `run_codex_loop.sh` 内置默认值，而不是一长串运行时参数。

4. `Validation Plan`
- Quick 模式检查（每轮）。
- Full 模式检查（里程碑或收尾）。
- 通过 / 失败阈值。
- 明确写出：一次成功且有证据记录的检查即可标记 PASS，但后续若有反证必须撤销 PASS。
- 明确写出：若后续证据推翻了旧验证，必须如何回滚。

5. `Assumptions And Risks`
- 明确写出未知项，以及 prompt 如何缓解这些未知。
- 明确写出是否检测到旧布局，以及它是如何被迁移 / 归档的。

## 质量门禁

在最终输出前，确认以下事项：

1. 确认 fresh worktree 隔离。
- 循环包创建在新的 git worktree 目录中。
- 返回命令从该 fresh worktree 启动，而不是从源仓库目录启动。

2. 确认布局迁移规则明确。
- prompt 明确区分新的规范布局和旧的 legacy 布局。
- prompt 明确区分 agent 常规可写文件与 runner 管理只读文件。
- 如果存在旧状态产物，它们被当作只读输入，并在需要时转移到 `legacy/`。
- prompt 只允许往新规范布局写入。

3. 确认 bootstrap 盘点要求明确。
- prompt 要求在 bootstrap 阶段使用一个或多个只读 subagent。
- prompt 明确提醒：实现可能已经部分完成。
- prompt 要求把恢复出的已有进展写入 `work_status.md` 和 `progress.md`。
- prompt 要求在 bootstrap 时记录 loop 起点 commit，并把它作为后续清理过期文件和临时 debug 代码的对照基线。

4. 确认 prompt 包含所有必需章节。
- 目标、规范布局、旧布局处理、worktree 规则、bootstrap 盘点、
  work status 结构、每轮流程、测试策略、更新规则、停止条件。

5. 确认反幻觉行为明确。
- 要求每轮都重新扫描并重新验证。
- 禁止盲信先前日志或消息。
- 要求显式携带原始提示词以及上一轮 work status / 检查状态。
- 要求提供“纠错”部分，说明哪些旧计划或旧 PASS 结论被修正。

6. 确认命令与路径一致。
- prompt 路径位于状态目录中。
- runner 位于 fresh worktree 根目录。
- runner 已经内置 prompt / state / original prompt / work status / progress / sleep 的默认路径。
- 使用 prompt 文件时，runner 会在每轮热加载该文件。
- state / original prompt / work status / progress 路径存在，或会由 runner 自动创建。

7. 确认可复现。
- 返回命令可以直接复制执行。
- fresh worktree 路径明确无歧义。
