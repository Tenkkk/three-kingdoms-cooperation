# Communication Protocol

## 1. Task Instructions to Workers (Outbound Prompt)

Every prompt sent to a Worker MUST contain the following structure:

```markdown
Claude:

## Analysis from Claude:

[Claude's output from the previous round / or plan summary]

## Review Conclusion from Codex: (if any)

[Codex's reply]

## Design Proposal from Gemini: (if any)

[Gemini's reply]

---

## Your Task

[Specific task: review / design / implement / respond to challenges]

## Verification Requirements

You must verify all technical claims by reading actual files and code. Do not answer from memory or inference.
If external dependencies, APIs, SDK versions, etc., are involved, please consult official documentation and attach source URLs.
If you cannot verify a claim, explicitly mark it as "unverified" rather than pretending to confirm it.

## Independent Verification Principle

The content you receive comes from other AI models. You must:
1. Independently verify all technical claims — read actual files, do not trust verbal descriptions.
2. If the conclusions of other models are wrong, point them out directly and provide code-level evidence.
3. Do not blindly agree just because the other party "said it first".
4. It is better to say "I'm not sure, need further verification" than to fabricate agreement.
5. If you need to check external documentation or API specs, do it directly and attach the URL.

## Reply Requirements

**Your reply MUST start with an identity prefix**: If you are Codex, start with "Codex: "; if you are Gemini, start with "Gemini: ".

## Reply Format

### For Review Tasks:
Use the following structure for each finding:

**[must-fix / should-fix / nitpick] Title**
- File: `path/to/file`
- Location: Line number or function name
- Issue: One sentence description
- Suggestion: How to fix it
- Evidence: Code snippet / file content / official doc link

### Conclusion Output (MANDATORY)
At the end of your reply, you MUST output the review conclusion in the following JSON format:

```json
{
  "verdict": "APPROVE | REVISE | REJECT",
  "summary": "One sentence summary",
  "findings": [
    {
      "severity": "must-fix | should-fix | nitpick",
      "title": "Title",
      "file": "path/to/file",
      "location": "Line number or function name",
      "issue": "Issue description",
      "suggestion": "Suggestion",
      "evidence": "Evidence or doc link"
    }
  ],
  "needs_user_decision": false,
  "open_questions": []
}
```
```

> **Note**: The verdict JSON is output by the Worker to stdout. Claude or `call-worker.sh` is responsible for extracting it from stdout and writing it to `.tk-meeting/<session>/<worker>-verdict.json`. During the review phase, the Worker runs in a read-only sandbox and cannot write files itself.

---

## 2. Attribution Standards

Every forwarded message must clearly indicate the source so the receiver knows "who said it":

- Citing other parties in the prompt to Codex: `## Analysis from Claude:` / `## Feedback from Gemini:`
- Citing other parties in the prompt to Gemini: `## Analysis from Claude:` / `## Feedback from Codex:`
- Forwarding User decisions to Worker: Start with `User:`
- **All messages uniformly use identity prefixes**: `Claude:` / `Codex:` / `Gemini:` / `User:`
- When Claude summarizes for the user, it also starts with `Claude:` (do not use variants like "My judgment").

---

## 3. Escalations Requiring User Decisions

When the following situations occur, Claude pauses the automated process and requests a user decision via the `AskUserQuestion` tool:

1. **Model Disagreements**: Two reviewers hold opposing views on the same issue.
2. **Directional Issues**: Non-purely technical judgments involving product requirements, tech stack selection, etc.
3. **Abnormalities**: Worker CLI execution fails, times out, or outputs abnormally.
4. **New Session Suggestion**: Claude or a Worker believes the current context is no longer suitable to continue.

Escalation Format:

```
Claude:

[Situation Explanation]

Codex: [View + Reason + Evidence] (Summarized)
Gemini: [View + Reason + Evidence] (Summarized)
Claude: [My Judgment — Inclination + Reason]

Please decide the direction.
```

When forwarding the user's decision to a Worker:

```
User: [User's decision content]
```

---

## 3.5 Implementation Gate (Three-way APPROVE Gate)

The threshold for convergence from the review phase to implementation:

1. **Codex's verdict = APPROVE**
2. **Gemini's verdict = APPROVE**
3. **Claude gives APPROVE after independent verification** (Claude must review the plan's current state itself and cannot just agree because the other two approved).

All three are indispensable. Only after all three have given APPROVE can Claude ask the user "Ready to start implementation?"

**Exception**: The user can actively say "Enough, start implementation" at any time to bypass the gate.

---

## 4. Session Management

### Session ID Extraction and Recording

After every Worker call, Claude MUST extract the session ID from the Worker's output and record it in `.tk-meeting/<session>/sessions.json`.

- **Codex**: `codex exec --json` first event `thread.started` contains `thread_id`; or extract from the stderr session banner.
- **Gemini**: `--output-format json` output contains session metadata; or extract from stderr/stdout session info.

### sessions.json Format

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

### Multi-round Context Persistence

- **Codex**: `codex exec resume <session-id> "follow-up"`
- **Gemini**: `gemini --resume <session-id> -p "follow-up"` or `gemini --resume latest -p "follow-up"` (resume mode must use `-p`, positional arguments will timeout).
- **Claude**: Itself is the current session, naturally maintains context.

---

## 5. Multi-round Review Prompt Structure (From Round 2)

Subsequent rounds **DO NOT require a full re-review**. They should address the findings from the previous round point-by-point and cross-reference the feedback from the other model.

### Template: Subsequent Round Review Prompt

```markdown
Claude:

## Background

This is round [N] of the review. In the previous round, you raised [X] findings. Claude has fixed them point-by-point.
Also attached is [Other Model]'s round [N-1] feedback for cross-reference.

## Your Findings from the Previous Round and Fix Status

### Finding 1: [Original Title]
- Your original feedback: [Summary]
- Claude's fix: [What was changed, attach file path and line number]
- Please verify: Is the fix sufficient?

### Finding 2: [Original Title]
- Your original feedback: [Summary]
- Claude's fix: [What was changed]
- Please verify: Is the fix sufficient?

[List all findings point-by-point]

## Feedback from [Other Model] (Cross-reference)

[Other Model] raised the following points in round [N-1] for your reference:
- [Summary 1]
- [Summary 2]

If you find any point from [Other Model] to be incorrect or if you have a different view, please point it out directly.

## Your Task

1. Verify point-by-point if the above fixes are sufficient (read actual files, do not trust descriptions).
2. If you find new issues, raise them according to the standard format.
3. Output the verdict JSON at the end.

## Reply Requirements

Your reply MUST start with "[Your Name]: ".
```

### Key Principles

- **Point-by-point Verification**: Do not generally say "everything is fixed". You must confirm point-by-point.
- **Cross-reference**: Refer to the other model's feedback. Point out directly when contradictions are found.
- **Incremental Review**: Only review the fixed parts + newly discovered issues. Do not require a full re-review.
- **Independent Judgment**: Do not lean towards REVISE just because the previous round was REVISE. If it is fixed, APPROVE.
