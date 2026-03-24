# CLI 调用规范速查

> Claude Code 的 Bash 工具运行在内置 bash 环境（Git Bash on Windows）。以下示例统一使用 bash 语法。

## Codex CLI

### 审查（只读，默认沙箱）

```bash
echo "<prompt>" | codex exec -
```

### 实施（需要改文件，workspace 写权限）

```bash
echo "<prompt>" | codex exec --full-auto -
```

### 长 prompt 通过文件传入

```bash
codex exec --full-auto -o output.md - < prompt.md
```

### 结果写文件（大输出防截断，stdout 仍有输出）

```bash
codex exec --full-auto -o .tk-meeting/<session>/codex-response.md - < prompt.md
```

### JSONL 事件流（程序化解析用，不直接展示给用户）

```bash
echo "<prompt>" | codex exec --full-auto --json -
```

### 会话恢复

```bash
# 标准路径：指定 session ID
codex exec resume <session-id> "follow-up prompt"

# 简易兜底：cwd 作用域下最近会话（多任务并行时可能串会话，慎用）
codex exec resume --last "follow-up prompt"
```

### 关键特性

- `exec` 模式：stderr = 实时进度，stdout = 最终结果
- 审查用默认只读沙箱（不加 `--full-auto`），实施才加 `--full-auto`（= `--sandbox workspace-write`）
- `--json`：输出 JSONL 事件流，事件类型包括 `thread.started`、`turn.started`、`turn.completed`、`turn.failed`、`item.*`、`error` 等——解析时应按 `type` 字段处理，不要硬编码枚举
- `-o <file>`：最终结果写文件，同时仍输出到 stdout
- `resume <session-id>`：恢复指定会话；`--last` 是 cwd 作用域简写

---

## Gemini CLI

### 审查（只读，默认审批模式）

```bash
gemini "<prompt>"
```

### 实施（自动批准工具调用）

```bash
gemini "<prompt>" --approval-mode yolo
```

### stdin 管道输入（长 prompt）

```bash
# 注意：不要同时传位置参数，否则会重复拼接
cat prompt.md | gemini --approval-mode yolo
```

### 文件注入（Gemini 特有 @ 语法）

> **限制**：`@file` 对被 `.gitignore` 或 `.geminiignore` 排除的文件**不可用**——Gemini 会静默跳过。`.orchestrator/` 目录在 `.gitignore` 中，因此该目录下的 prompt 文件不能用 `@file` 注入，需改用 `$(cat file)` 内联传入。

```bash
# 非 gitignored 文件：推荐用 @file
gemini "审查 @path/to/plan.md 这份预案" --approval-mode yolo

# gitignored 文件（如 .orchestrator/ 下的 prompt）：改用内联
gemini "$(cat .tk-meeting/.../prompt.md)" --approval-mode yolo
```

### 输出写文件

```bash
gemini "<prompt>" --approval-mode yolo > .tk-meeting/<session>/gemini-response.md
```

### 结构化 JSON 输出（程序化解析用）

```bash
gemini "<prompt>" --output-format json
```

### 会话恢复

> **重要**：resume 模式下必须用 `-p` 传 prompt，位置参数会导致超时卡住（Codex 实测确认）。

```bash
# 恢复 cwd 下最近会话（必须用 -p）
gemini --resume latest -p "follow-up prompt"

# 恢复指定会话（必须用 -p）
gemini --resume <session-id> -p "follow-up prompt"
```

### 关键特性

- 位置参数传入 prompt（新会话推荐写法；`-p` 仍兼容）
- **resume 模式必须用 `-p`**：`gemini --resume <id> -p "prompt"`（位置参数在 resume 下会超时）
- `--approval-mode yolo`：自动批准所有操作（推荐写法；`-y` 仍兼容但不推荐）
- `@path/to/file`：注入文件内容到 prompt，推荐作为传递预案和上下文的主要方式
- `--resume latest`：恢复 cwd 下最近会话；`--resume <session-id>`：恢复指定会话
- `--output-format json`：结构化输出（含 `session_id`）
- `--output-format stream-json`：实时事件流（仅用于程序化监控，不适合终端直出——会刷屏）
- 默认文本输出模式对用户最友好，终端实时流式可读

---

## 调用选择矩阵

| 场景 | Codex 命令 | Gemini 命令 |
|------|-----------|------------|
| 审查预案（只读） | `echo "<prompt>" \| codex exec -` | `gemini "<prompt>"` |
| 审查并改文件（实施） | `echo "<prompt>" \| codex exec --full-auto -` | `gemini "<prompt>" --approval-mode yolo` |
| 文件注入传递上下文 | 工作目录内文件自动可读 | `gemini "审查 @plan.md"` |
| 多轮对话（续上轮） | `codex exec resume <sid> "..."` | `gemini --resume <sid> -p "..."` |
| 大输出防截断 | 加 `-o result.md` | 加 `> result.md` |
| 程序化解析 | 加 `--json` | 加 `--output-format json` |

---

## 跨平台备注

PowerShell 不支持 `<` 重定向。等效写法：
- `Get-Content -Raw prompt.md | codex exec --full-auto -o output.md -`
- `Get-Content -Raw prompt.md | gemini --approval-mode yolo`

## Phase 2 验证结果（2026-03-24 实测）

- ✅ Gemini `@file` 注入在 headless 模式下可用（非 gitignored 文件）
- ⚠️ Gemini `@file` 对 `.gitignore` 排除的文件**不可用**——Phase 3 端到端测试暴露，`.orchestrator/` 下的 prompt 文件被静默跳过
- ✅ Session ID 提取：Codex `--json` 首条 `thread.started` 含 `thread_id`；Gemini `--output-format json` 顶层含 `session_id`
- ✅ Codex session ID 也可从 stderr banner 的 `session id:` 行提取
- ✅ Gemini resume 必须用 `-p` 传 prompt（位置参数会超时，Codex 审查 + 实测确认）

## Worker 输出可见性

- Claude Code 的 Bash 工具在命令**完成后**才将 stdout/stderr 一次性返回给用户，不支持实时流式透传
- `call-worker.sh` 将 Worker 输出同时 `tee` 到 `${OUTPUT_FILE}.stream.log`
- 用户可在 IDE 中另开终端执行 `tail -f <stream_log>` 实时逐行查看 Worker 输出
- Claude 在调用 Worker 前会告知用户 stream log 路径
