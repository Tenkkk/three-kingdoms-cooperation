![alt text](img.png)

# 三国开会 (/tk)

**[English](README.md)**

### 如果你同时拥有3大巨头的Agent配额，那么恭喜你，使用此技能，你的方案设计、代码质量将更上一层楼。

#### 根据难度和工作量，平均整个过程可能长达数十分钟，但你会得到一份每次满意舒心的答卷。

Claude Code 的多模型会审与协作实施技能。Claude 作为主持人，调度 Codex (GPT) 和 Gemini CLI 子进程进行预案审查、代码审查和协作实施。

## 工作原理

```
你: "/tk" 或 "开会"
  ↓
Claude — 会议主持人 + 执行者
  ├── Codex (GPT) — 代码审查 + 把关者
  └── Gemini — 设计 + 前端 + 补充视角
```

**三个阶段：**

1. **推敲** — Claude 帮你把模糊想法变成结构化预案
2. **会审** — Codex 和 Gemini 独立审查预案，迭代直到三方全部 APPROVE
3. **实施** — Claude 写代码，Codex 逐步审查，Gemini 协助视觉/UX 部分

## 前提条件

- 已安装并配置 [Claude Code](https://docs.anthropic.com/en/docs/claude-code/overview)
- 已安装 [Codex CLI](https://github.com/openai/codex)（`npm install -g @openai/codex`）
- 已安装 [Gemini CLI](https://github.com/google-gemini/gemini-cli)（`npm install -g @google/gemini-cli`）

## 情况

3个Agent开会讨论你的需求，决定质量上限的核心是GPT(codex)，决定下限的是Claude code，而Gemini可以填补它们的视野和局限性。
所以推荐至少拥有codex和Claude code的情况下，使用此技能。
如果你只有Claude code，它也可以帮助你的claude更好的思考和实践。

## 安装

```bash
npx skills add Tenkkk/three-kingdoms-cooperation
```

## 使用方式

以下任何一种方式触发：

- `/tk`
- "开会"
- "会审"
- "让 codex 和 gemini 看看"
- "多模型审查"
- "three kingdoms"

### 示例

```
你: /tk 我想给 Todo 模型加一个优先级字段

Claude: [和你推敲预案]
Claude: "预案完成，开始会审？"

你: "开始"

Claude → Codex: [审查预案，找出问题]
Claude → Gemini: [审查预案，补充视角]
Claude: [迭代直到三方 APPROVE]
Claude: "三方全部批准，开始实施？"

你: "开始"

Claude: [逐步实施，Codex 逐步审查]
```

## 核心特性

- **三方 APPROVE 门禁** — Codex + Gemini + Claude 必须各自独立批准后才能进入实施
- **逐步审查** — 每个实施步骤都必须经过 Codex 审查后才能继续下一步
- **独立思考** — Worker 被要求独立验证技术声明，不盲目附和
- **消息归属** — 每条消息都标注说话者身份（Claude/Codex/Gemini）
- **会话管理** — 跟踪每个 Worker 的 session ID，支持多轮对话
- **实时日志** — Worker 输出同时写入日志文件，在第二终端 `tail -f` 可实时查看

## 架构

纯 Agent 技能 — 无 TypeScript、无 Python、无构建步骤、无依赖。只有 Markdown 指令和一个 Bash 脚本。

```
skills/
  tk/
    SKILL.md                 — 技能主文件
    references/
      cli-reference.md       — Codex/Gemini CLI 语法速查
      communication-protocol.md — 消息格式、verdict JSON 结构
      role-presets.md         — 角色预设与 prompt 模板
    scripts/
      call-worker.sh         — 统一 Worker 调用脚本
  detect-workers/
    SKILL.md                 — 快速检测已安装的 CLI Worker
```

## 协作模式

本技能源自 10+ 个真实生产会话的实战提炼，支持三种协作模式：


| 模式        | 说明                      | 典型场景 |
| --------- | ----------------------- | ---- |
| **会审制**   | 多模型审阅同一份预案，迭代达成共识       | 预案审查 |
| **红蓝对抗**  | 一方批评、一方修改、第三方仲裁         | 方案辩论 |
| **指挥-执行** | 一方生成 Prompt、一方执行代码、一方审查 | 代码实施 |


## 开源协议

[CC BY-NC 4.0 (署名-非商业性使用)](LICENSE)