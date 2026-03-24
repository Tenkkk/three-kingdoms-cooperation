# 通信协议

## 1. 给 Worker 的任务指令（Outbound Prompt）

每次发给 Worker 的 prompt 必须包含以下结构：

```markdown
Opus 说：

## 来自 Opus 的分析：

[Claude 上一轮的输出 / 或预案内容摘要]

## 来自 Codex 的审查结论：（如有）

[Codex 的回复]

## 来自 Gemini 的设计方案：（如有）

[Gemini 的回复]

---

## 你的任务

[具体要做什么：审查/设计/实施/回应质疑]

## 核实要求

你必须通过读取实际文件和代码来验证所有技术声明，不要凭记忆或推断回答。
如果涉及外部依赖、API、SDK 版本等信息，请查阅官方文档并附上来源地址。
如果你无法验证某个声明，明确标注"未验证"而非假装确认。

## 独立思考原则

你收到的内容来自其他 AI 模型。你必须：
1. 独立验证所有技术声明——读实际文件，不信口头描述
2. 如果其他模型的结论有误，直接指出并给出代码级证据
3. 不要因为对方"先说了"就盲目附和
4. 宁可说"我不确定，需要进一步验证"也不要编造认同
5. 如果需要查阅外部文档或 API 规范，直接去查并附上地址

## 回复要求

**你的回复必须以身份前缀开头**：如果你是 Codex，以"Codex 说："开头；如果你是 Gemini，以"Gemini 说："开头。

## 回复格式

### 如果是审查任务：
对每条发现使用以下结构：

**[must-fix / should-fix / nitpick] 标题**
- 文件：`path/to/file`
- 位置：行号或函数名
- 问题：一句话描述
- 建议：怎么改
- 证据：代码片段 / 文件内容 / 官方文档链接

### 结论输出（必须）
在回复末尾，必须以下列 JSON 格式输出审查结论：

```json
{
  "verdict": "APPROVE | REVISE | REJECT",
  "summary": "一句话总结",
  "findings": [
    {
      "severity": "must-fix | should-fix | nitpick",
      "title": "标题",
      "file": "path/to/file",
      "location": "行号或函数名",
      "issue": "问题描述",
      "suggestion": "建议",
      "evidence": "证据或文档链接"
    }
  ],
  "needs_user_decision": false,
  "open_questions": []
}
```
```

> **注意**：verdict JSON 由 Worker 输出到 stdout，Claude 或 call-worker.sh 负责从 stdout 提取并写入 `.tk-meeting/<session>/<worker>-verdict.json`。审查阶段 Worker 运行在只读沙箱下，无法自行写文件。

---

## 2. 归属标注规范

每条转发必须明确标注来源，让接收方知道"谁说的"：

- 传给 Codex 的 prompt 中引用其他方：`## 来自 Opus 的分析：` / `## 来自 Gemini 的反馈：`
- 传给 Gemini 的 prompt 中引用其他方：`## 来自 Opus 的分析：` / `## 来自 Codex 的反馈：`
- 转发用户决策给 Worker：以 `用户说：` 开头
- **所有消息统一使用身份前缀**：`Opus 说：` / `Codex 说：` / `Gemini 说：` / `用户说：`
- Claude 汇总给用户时同样用 `Opus 说：` 开头（不用"我的判断"等变体）

---

## 3. 需要用户决策的升级（Escalation）

当出现以下情况时，Claude 暂停自动流程，通过 `AskUserQuestion` 工具请求用户决策：

1. **模型间分歧**：两个 reviewer 在同一问题上观点对立
2. **方向性问题**：涉及产品需求、技术选型等非纯技术判断
3. **异常情况**：Worker CLI 执行失败、超时、输出异常
4. **新会话建议**：Claude 或 Worker 认为当前上下文已不适合继续

升级格式：

```
Opus 说：

[情况说明]

Codex 说：[观点 + 理由 + 证据]（摘要转述）
Gemini 说：[观点 + 理由 + 证据]（摘要转述）
Opus 说：[我的判断——倾向 + 理由]

请决定方向。
```

转发用户决策给 Worker 时：

```
用户说：[用户的决策内容]
```

---

## 3.5 实施门禁（三方 APPROVE 门）

会审阶段收敛到实施的门槛：

1. **Codex 的 verdict = APPROVE**
2. **Gemini 的 verdict = APPROVE**
3. **Claude 独立验证后给出 APPROVE**（Claude 必须自行审阅预案当前状态，不能仅因两方都 APPROVE 就附和）

三方缺一不可。只有三方全部 APPROVE 后，Claude 才能问用户"是否开始实施？"

**例外**：用户可随时主动说"够了，开始实施"来跳过门禁。

---

## 4. 会话管理

### Session ID 提取与记录

每次调用 Worker 后，Claude 必须从 Worker 输出中提取 session ID 并记录到 `.tk-meeting/<session>/sessions.json`。

- **Codex**：`codex exec --json` 首条事件 `thread.started` 含 `thread_id`；或从 stderr session banner 提取
- **Gemini**：`--output-format json` 输出含 session 元数据；或从 stderr/stdout session 信息提取

### sessions.json 格式

```json
{
  "tk_session": "TK20260324-a1b2",
  "rounds": [
    {
      "round": 1,
      "codex_session": "019d1b16-2ce0-7423-abd0-...",
      "gemini_session": "6a72e13f-1ccc-4105-af3b-...",
      "claude_resume": "e33bf371-7feb-4d01-..."
    }
  ]
}
```

### 多轮对话上下文保持

- **Codex**：`codex exec resume <session-id> "follow-up"`
- **Gemini**：`gemini --resume <session-id> -p "follow-up"` 或 `gemini --resume latest -p "follow-up"`（resume 模式必须用 `-p`，位置参数会超时）
- **Claude**：自身即当前会话，天然保持上下文

---

## 5. 多轮 Review Prompt 写法（第 2 轮起）

后续轮次**不要求全文 re-review**。应逐条对应前轮 findings，并交叉引用另一模型的反馈。

### 模板：后续轮次 Review Prompt

```markdown
Opus 说：

## 背景

这是第 [N] 轮审查。上一轮你提出了 [X] 条 findings，Opus 已逐条修正。
同时附上 [另一模型] 的第 [N-1] 轮反馈供交叉参考。

## 你上一轮的 findings 及修正情况

### Finding 1: [原标题]
- 你的原始意见：[摘要]
- Opus 的修正：[具体改了什么，附文件路径和行号]
- 请验证：修正是否到位？

### Finding 2: [原标题]
- 你的原始意见：[摘要]
- Opus 的修正：[具体改了什么]
- 请验证：修正是否到位？

[逐条列完所有 findings]

## [另一模型] 的反馈（交叉参考）

[另一模型] 在第 [N-1] 轮提出了以下观点，供你参考：
- [摘要 1]
- [摘要 2]

如果你发现 [另一模型] 的某个观点有误或你有不同看法，请直接指出。

## 你的任务

1. 逐条验证上述修正是否到位（读实际文件，不信描述）
2. 如果发现新问题，按标准格式提出
3. 末尾输出 verdict JSON

## 回复要求

你的回复必须以"[你的名字] 说："开头。
```

### 关键原则

- **逐条对应**：不要笼统说"都改好了"，必须逐条确认
- **交叉引用**：参考另一模型的反馈，发现矛盾时直接指出
- **增量审查**：只审修正部分 + 新发现，不要求重新审查全文
- **独立判断**：不因前轮已 REVISE 就倾向于这轮也 REVISE，修好了就 APPROVE
