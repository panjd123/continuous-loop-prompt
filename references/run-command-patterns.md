# 运行命令模式

最终必须只返回**一条**可直接执行的命令。
生成出来的 `run_codex_loop.sh` 必须已经内置
prompt / state / original-prompt / work-status / progress / sleep 的默认值，
并且它必须位于**fresh worktree**中。最终命令通常应该是先 `cd` 进入该
fresh worktree，再执行 `./run_codex_loop.sh`。

## 优先形式（fresh worktree 已准备好）

```bash
cd /abs/path/to/fresh-worktree && ./run_codex_loop.sh
```

当技能已经完成以下工作时，使用这一形式：

- 已创建 fresh worktree
- 已把 prompt 写入规范状态目录
- 已在该 worktree 中安装 runner

runner 必须保证：

- 运行时 prompt 会包含原始用户提示词以及上一轮 work-status 内容
- 每个检查项在一次成功且有证据记录后即可 PASS，但后续若出现反证必须撤销 PASS
- work-status 文件默认每轮都必须更新
- 每轮结束都允许重写 / 重置错误的旧计划，并撤销错误的旧 PASS
- 默认 `sleep` 为 `0`，除非用户明确要求非零延迟
- 当 prompt 来自文件时，该文件的修改会在下一轮自动生效，无需重启循环

## Bootstrap 辅助命令（技能执行阶段）

在技能执行过程中，先使用 bootstrap 辅助脚本创建 fresh worktree 并安装 runner：

```bash
bash /root/.codex/skills/continuous-loop-prompt/scripts/bootstrap_fresh_loop_worktree.sh \
  --source-repo .
```

在技能把新 worktree 和 prompt 都准备好之后，返回一条简单命令：

```bash
cd /abs/path/to/fresh-worktree && ./run_codex_loop.sh
```

不要返回那种仍依赖旧源码目录中手工修改的伪命令。

## 返回风格

- 把命令放在普通代码块中返回。
- 确保命令可以直接复制执行。
