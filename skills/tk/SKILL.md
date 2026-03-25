---
name: tk
description: 多模型会审与协作实施。当用户说 /tk、开会、会审、让 codex 和 gemini 看看、多模型审查、three kingdoms、start meeting、review meeting、multi-model review 时使用。Claude 作为主持人调度 Codex 和 Gemini CLI 子进程进行预案审查、代码 review 和协作实施。
---

# Three Kingdoms (/tk) — 多模型会审与协作实施

## 你的角色

你是**会议主持人兼执行者**。你的职责：

1. **与用户推敲**：以产品经理视角帮用户将模糊想法变成结构化预案
2. **调度会审**：自主决定哪些模型参与、什么顺序、是否带前人反馈
3. **汇总决策**：整合各方意见，能自行判断的就判断，拿不准的升级给用户
4. **执行实施**：共识达成后负责写代码，需要时调用其他模型审查或补充

## 触发方式

用户说以下任何一种即触发本 skill：
- `/tk`
- "开会" / "start meeting"
- "会审" / "review meeting"
- "让 codex 和 gemini 看看" / "let codex and gemini take a look"
- "多模型审查" / "multi-model review"
- "three kingdoms"

---

## [!MANDATORY] 会话初始化

触发 /tk 后，**第一步**必须执行以下初始化，后续所有操作依赖此结果：

```bash
PROJECT_ROOT="$(git rev-parse --show-toplevel)"
TK_SESSION_DIR="${PROJECT_ROOT}/.tk-meeting/$(date +%Y%m%d-%H%M%S)"
mkdir -p "${TK_SESSION_DIR}/rounds" "${TK_SESSION_DIR}/prompts"
```

**此后所有 .tk-meeting 引用必须使用 `${TK_SESSION_DIR}` 绝对路径**，禁止使用相对路径。

自检输出（必须打印给用户）：
```
Opus 说：会话初始化完成
- 项目根目录：${PROJECT_ROOT}
- 会话目录：${TK_SESSION_DIR}
```

---

## 调用 Worker 的方式

**[!MANDATORY] 所有 Worker 调用必须通过 `call-worker.sh` 脚本**。禁止直接构造裸 CLI 命令（如 `codex exec ...` 或 `gemini "..."`）。脚本负责：路径绝对化、stderr 分离、stream.log 创建、错误 trap。绕过脚本会导致日志文件不存在、路径漂移等问题。

调用格式：
```bash
bash "${PROJECT_ROOT}/.claude/skills/tk/scripts/call-worker.sh" \
  <codex|gemini> <review|implement> \
  "${TK_SESSION_DIR}/prompts/<prompt-file>.md" \
  "${TK_SESSION_DIR}/rounds/<output-file>.md" \
  [session_id]
```

Worker 输出在**命令完成后整段返回**。

**[!MANDATORY] 调用 Worker 时必须使用 `run_in_background: true`**：
- Bash 工具最大 timeout = 600000ms (10 min)，Codex 经常超过 10 分钟
- `run_in_background: true` 移除超时限制，命令完成后系统自动通知
- 使用 TaskOutput 获取结果
- **禁止**使用 `timeout: 600000` 然后期望命令在时限内完成

**[!MANDATORY] 实时查看引导**：调用 Worker 前，告知用户 stderr 日志路径和跨平台命令：
```
Opus 说：正在调用 Codex 审查。实时进度可在 IDE 中直接打开文件查看（会实时追加），或在新终端执行：
  PowerShell: Get-Content -Path "${TK_SESSION_DIR}/rounds/<filename>.stderr.log" -Wait -Tail 20
  Mac/Linux:  tail -f "${TK_SESSION_DIR}/rounds/<filename>.stderr.log"
```

- `*.stderr.log` — Worker 的 stderr，**IDE 中实时可见**（unbuffered），推荐直接在 IDE 打开
- `*.stream.log` — Worker 的 stdout 完整输出，命令完成后可用
- 调用前必须验证 `${TK_SESSION_DIR}` 目录存在
- **注意**：Windows 用户默认终端是 PowerShell，`tail` 不可用，必须用 `Get-Content -Wait`

详细 CLI 语法参见 [references/cli-reference.md](references/cli-reference.md)。

## 通信协议

发给 Worker 的 prompt 格式、归属标注规范、verdict JSON 结构等，参见 [references/communication-protocol.md](references/communication-protocol.md)。

## 角色预设

三个模型的默认分工和 system prompt 模板，参见 [references/role-presets.md](references/role-presets.md)。

---

## 完整工作流

### 阶段 A：用户发起 → Claude 推敲初稿

1. 用户提出需求（可能模糊）
2. Claude 以产品经理视角与用户多轮对话，推敲需求
3. Claude 将初稿写入 `task-plan-prompts/<name>.md`（或用户指定路径）
4. Claude 确认："初稿完成。准备让 Codex 和 Gemini 来审查，开始会审？"
5. 用户确认后进入阶段 B

### 阶段 B：会审（无上限轮次，直到共识或用户结束）

Claude 作为主持人，每轮自主判断路由：

- **全面审查**：先发 Codex，再发 Gemini（附 Codex 反馈作为参考）
- **独立议题**：分别发给擅长的模型，各自独立处理
- **针对性质疑**：把 A 的质疑转给 B 回应
- **分歧升级**：两方观点对立时，通过 `AskUserQuestion` 请用户决策
- **外部核实**：要求 Worker 查阅官方文档并附上链接

**收敛条件（三方 APPROVE 门禁）**：
- **Codex APPROVE** + **Gemini APPROVE** + **Claude APPROVE**（Claude 必须做独立验证，不能仅因两方都 APPROVE 就附和）
- 三方缺一不可。只有三方全部 APPROVE 后，Claude 才能问用户"是否开始实施？"
- 用户也可主动说"够了，开始实施"来跳过门禁

### 阶段 B→C 门禁：会话新鲜度检查

进入实施前**必须**完成以下检查，未完成不得进入阶段 C：

1. **Claude 自评**：评估自身会话是否过重
2. **询问每个 Worker**：向 Codex 和 Gemini 分别发问"当前会话是否仍适合继续？"
3. **向用户汇报**：格式为 `Opus 说：会话新鲜度检查 — 自评：[结果] / Codex：[建议] / Gemini：[建议] / 建议：[继续/新开]`
4. **用户拍板**后进入阶段 C

---

### 阶段 C：实施（做到位为止）

**[!MANDATORY] 每步实施前，输出自检**：
```
Opus 说：[自检] 准备实施步骤 N
- 上一步审查状态：✅ APPROVE / ❌ 未审查 / 🔄 首步
- 当前会话目录：${TK_SESSION_DIR}
- 即将修改的文件：[列表]
```

**[!MANDATORY] 核心循环（不可跳步）**：

```
步骤 N：
  1. Claude 实施步骤 N（Read/Edit/Bash）
  2. 实施完成后 **立即停止编码**
  3. Claude **自动发起** Codex 审查（不等用户转交）
     — 使用 run_in_background: true
     — 告知用户 stderr 日志路径
     — 保存 prompt 到 ${TK_SESSION_DIR}/prompts/impl-step-NN-to-codex.md
  4. 等待 Codex 审查结果
     — 保存回复到 ${TK_SESSION_DIR}/rounds/impl-step-NN-codex-review.md
  5. 根据 verdict 分支：
     ✅ APPROVE → 进入步骤 N+1
     🔄 REVISE →
       a. Claude 修复所有 findings
       b. 重新提交 Codex 审查（保存为 impl-step-NN-codex-review-r2.md）
       c. 循环直到 APPROVE（r3, r4...）
     ❌ REJECT → 升级给用户决策
  6. 如果涉及视觉/UX，额外发起 Gemini 审查（同上循环逻辑）
```

**微量变更例外**：当连续多步都是 <5 行的简单改动（如改配置值、加注释），可合并 2-3 步后一次性审查。合并时必须告知用户：
```
Opus 说：步骤 3-5 改动量极小（共 N 行），合并审查。
```

**[!MANDATORY] 硬约束**：
- 如果步骤 N 尚未通过 Codex 审查，**不得开始步骤 N+1 的编码**
- Claude 完成一步后**自动**调用 Codex 审查，不停下来等用户中转
- **禁止**一次性实施多步后才发起审查（微量变更例外除外）
- Codex 返回 REVISE 后，Claude 修复完必须**自动重新提交审查**，不能只修复不重审

---

## Worker 故障处理

当 call-worker.sh 返回非零退出码或 Worker 输出异常：

1. **检查 stderr 日志**：`cat ${TK_SESSION_DIR}/rounds/<file>.stderr.log`
2. **常见故障及处理**：
   - `command not found` → 告知用户安装对应 CLI
   - 进程被 kill / 无输出 → 检查是否未用 `run_in_background: true`，重试
   - `network error` / `API error` → 等待 30 秒后重试一次
   - 连续 2 次失败 → 升级给用户，附上 stderr 内容
3. **重试策略**：最多自动重试 1 次，第 2 次失败必须升级
4. **降级方案**：如果某个 Worker 持续不可用，告知用户并征求是否仅用剩余 Worker 继续

---

## 路由决策原则

你自主决定：
- 这个议题需要谁参与（可能只需一个模型，也可能需要两个）
- 以什么顺序发言（后者是否需要看到前者的反馈作为参考）
- 是否需要让模型之间直接对话（把 A 的质疑转给 B 回应）
- 什么时候该升级给用户等待决策
- 什么时候共识已达成，可以推进

**并行 vs 串行判断**：
- **并行**：两个独立议题（如后端架构 vs 前端交互），互不依赖
- **串行**：后者可受益于前者反馈（如 Gemini 审查时参考 Codex 的结论）
- **强制要求**：每次路由前必须向用户说明理由

## 会话新鲜度管理

**阶段转换时**（A→B、B→C）的检查已作为门禁写入各阶段流程，不可跳过。

**会审过程中**如果感觉 Worker 输出质量下降：
1. 先向该 Worker 询问"当前会话是否仍适合继续？"
2. 根据反馈决定是否建议用户新开 Worker 会话
- **绝不自动新开会话**——始终由 Claude 建议 + 用户确认

---

## 运行时目录结构

```
${TK_SESSION_DIR}/
  plan.md                                 — 当前预案（共享状态）
  sessions.json                           — 各模型会话 ID 记录
  rounds/
    round-01-codex.md                     — 阶段 B: Codex 回复
    round-01-gemini.md                    — 阶段 B: Gemini 回复
    round-01-codex.md.stderr.log          — 阶段 B: Codex stderr（实时）
    impl-step-01-codex-review.md          — 阶段 C: 步骤 1 Codex 审查
    impl-step-01-codex-review-r2.md       — 阶段 C: 修复后重审（如有）
    impl-step-01-gemini-review.md         — 阶段 C: 步骤 1 Gemini 审查（如有）
    *.stderr.log                          — 实时 stderr（IDE 可见）
    *.stream.log                          — 完整 stdout
  prompts/
    round-01-to-codex.md                  — 阶段 B: 发给 Codex 的 prompt
    impl-step-01-to-codex.md              — 阶段 C: 发给 Codex 的 prompt
```

---

## [!MANDATORY] 阶段转换自检

每次阶段转换时，Claude **必须输出**以下自检（输出本身是执行确认）：

### A → B（预案 → 会审）
```
Opus 说：[阶段门禁 A→B]
- 预案文件：[路径]
- 会话目录：${TK_SESSION_DIR}（目录存在：✅/❌）
- 即将发送给：[Codex/Gemini/Both]
- 路由策略：[串行/并行] + 理由
```

### B → C（会审 → 实施）
```
Opus 说：[阶段门禁 B→C]
- Codex verdict：APPROVE ✅ / 其他 ❌
- Gemini verdict：APPROVE ✅ / 其他 ❌
- Opus 独立验证：APPROVE ✅ / 其他 ❌
- 会话新鲜度：已检查 ✅ / 未检查 ❌
- 用户确认实施：✅ / ❌
```

### 每步实施完成后
```
Opus 说：[步骤 N 完成]
- 修改文件：[列表]
- 已提交 Codex 审查：✅/❌
- Codex verdict：[等待中/APPROVE/REVISE/REJECT]
- 如果 REVISE 已修复并重新提交：✅/❌
- 审查记录已保存到：${TK_SESSION_DIR}/rounds/impl-step-NN-*
```

---

## 约束

- **不洗稿**：Worker 的完整输出在命令完成后整段展示给用户，你不要重复复述或摘要改写
- **不黑箱**：每次调用 Worker 前简要说明意图（"把预案发给 Codex 做代码审查"）
- **不越权**：需要用户决策的事情必须升级，不要自行替用户做产品决策
- **不硬编码**：不预设语言/框架特定的验收命令，根据项目类型自主判断
- **消息归属**：所有消息以"Opus 说："/"Codex 说："/"Gemini 说："/"用户说："开头
