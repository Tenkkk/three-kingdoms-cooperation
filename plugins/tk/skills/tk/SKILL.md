---
name: tk
description: 多模型会审与协作实施。当用户说 /tk、开会、会审、让 codex 和 gemini 看看、多模型审查、three kingdoms 时使用。Claude 作为主持人调度 Codex 和 Gemini CLI 子进程进行预案审查、代码 review 和协作实施。
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
- "开会"
- "会审"
- "让 codex 和 gemini 看看"
- "多模型审查"
- "three kingdoms"

## 调用 Worker 的方式

通过 Bash 工具调用 CLI 子进程。Worker 输出在**命令完成后整段返回**给用户。

**可选实时查看**：Worker 输出同时写入 `.tk-meeting/<session>/` 下的 `.stream.log` 文件。调用 Worker 前，Claude 会告知用户 stream log 路径，用户可在 IDE 中另开一个终端执行 `tail -f <stream_log>` 实时逐行观看 Worker 输出。

详细 CLI 语法参见 [references/cli-reference.md](references/cli-reference.md)。

## 通信协议

发给 Worker 的 prompt 格式、归属标注规范、verdict JSON 结构等，参见 [references/communication-protocol.md](references/communication-protocol.md)。

## 角色预设

三个模型的默认分工和 system prompt 模板，参见 [references/role-presets.md](references/role-presets.md)。

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

### 阶段 C：实施（做到位为止）

**硬性流程（编号循环，不可跳步）**：

```
对预案中的每个步骤 N：
  1. Claude 实施步骤 N（Read/Edit/Bash）
  2. 实施完成后 **立即停止编码**
  3. Claude **自动发起** Codex 审查（不等用户转交）
     — 告知用户 stream log 路径，提示可选 tail -f
  4. 等待 Codex 审查结果
  5. 如果涉及视觉/UX，自动发起 Gemini 审查
  6. 审查全部通过后，才可进入步骤 N+1
```

**硬约束**：
- 如果步骤 N 尚未通过 Codex 审查，**不得 Edit/Bash 改步骤 N+1 的代码**
- Claude 完成一步后**自动**调用 Codex 审查，除非 CLI 故障或需要用户裁决，否则不停下来等用户中转
- **禁止**一次性实施多步后才发起审查

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
- **强制要求**：每次路由前必须向用户说明理由（"Codex 先审架构，Gemini 再审交互并参考 Codex 反馈"或"两个议题独立，并行发出"）

## 会话新鲜度管理

**阶段转换时**（A→B、B→C）的检查已作为门禁写入各阶段流程，不可跳过。

**会审过程中**如果感觉 Worker 输出质量下降：
1. 先向该 Worker 询问"当前会话是否仍适合继续？"
2. 根据反馈决定是否建议用户新开 Worker 会话
- **绝不自动新开会话**——始终由 Claude 建议 + 用户确认

## 运行时目录

每次会审在 `.tk-meeting/<session-id>/` 下创建运行时数据：

```
.tk-meeting/<session-id>/
  plan.md                         — 当前预案文件（共享状态）
  sessions.json                   — 各模型会话 ID 记录
  rounds/
    round-01-codex.md             — 第 1 轮 Codex 的原始回复
    round-01-gemini.md            — 第 1 轮 Gemini 的原始回复
  prompts/
    round-01-to-codex.md          — 发给 Codex 的完整 prompt（可审计）
    round-01-to-gemini.md         — 发给 Gemini 的完整 prompt
```

## 约束

- **不洗稿**：Worker 的完整输出在命令完成后整段展示给用户，你不要重复复述或摘要改写
- **不黑箱**：每次调用 Worker 前简要说明意图（"把预案发给 Codex 做代码审查"）
- **不越权**：需要用户决策的事情必须升级，不要自行替用户做产品决策
- **不硬编码**：不预设语言/框架特定的验收命令，根据项目类型自主判断
- **消息归属**：所有消息以"Opus 说："/"Codex 说："/"Gemini 说："/"用户说："开头
