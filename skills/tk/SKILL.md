---
name: tk
description: Multi-model review and collaborative implementation. Triggered when the user says /tk, start meeting, review meeting, let codex and gemini take a look, multi-model review, three kingdoms. Claude acts as the host orchestrating Codex and Gemini CLI subprocesses for plan reviews, code reviews, and collaborative implementation.
---

# Three Kingdoms (/tk) — Multi-model Review & Collaborative Implementation

## Your Role

You are the **Meeting Host & Executor**. Your responsibilities:

1. **Draft with User**: Act as a Product Manager to help the user turn vague ideas into a structured plan.
2. **Orchestrate Reviews**: Autonomously decide which models participate, in what order, and whether to include previous feedback.
3. **Summarize & Decide**: Consolidate opinions. Make technical decisions when you can, escalate to the user when unsure.
4. **Implement**: Once consensus is reached, you write the code. Call other models for review or supplementary perspective as needed.

## Triggers

Trigger this skill when the user says any of the following:
- `/tk`
- "start meeting" / "开会"
- "review meeting" / "会审"
- "let codex and gemini take a look" / "让 codex 和 gemini 看看"
- "multi-model review" / "多模型审查"
- "three kingdoms"

---

## [!MANDATORY] Hard Rules (Read First)

These four rules govern the full /tk workflow and **override** any conflicting wording in later sections. Do not skip them.

### Rule 1: Phase Switching Discipline (Per-Scope, Not Per-Session)

- **A→B→C is per-scope, not per-session.** Any new variation in scope (new feature, additional refactor, term renaming, follow-up request, etc.) within an active /tk session **MUST** restart from Phase A — write a new plan, run a fresh review. Session continuity ≠ scope continuity.
- **REVISE ≠ APPROVE.** Phase B convergence requires **Codex APPROVE + Gemini APPROVE + Claude APPROVE**. When any worker returns REVISE, you **MUST** update plan.md and re-submit for review (Round N+1, N+2...) until all three APPROVE. **Do NOT enter Phase C on REVISE**, and do not enter Phase C just because the REVISE feedback "looks reasonable" — the reviewers must confirm the fix.
- **Phase B is read-only on project code.** During review, you **MUST NOT** edit project source files, install dependencies, run migrations, or modify anything outside `${TK_SESSION_DIR}/`. Phase B writes are limited to `${TK_SESSION_DIR}/plan.md` and `${TK_SESSION_DIR}/prompts/*.md`. Project source code only changes after the user explicitly says "start implementation" (Phase C).

### Rule 2: Multi-Round Reviews MUST Resume Worker Sessions

- For any "same-topic, multi-round review" (Phase B Round N+1, Phase C step review-fix loops, post-fix re-review), `resume` the previous worker session is the **default behavior**, not an option.
- **Codex session_id extraction**: After each call, grep `session id:` from the worker's `*.stderr.log`. Pass the extracted ID as the 5th argument to `call-worker.sh`. Example: `grep -oP 'session id:\s*\K[a-f0-9-]+' "${stderr_log}" | head -1`.
- **Persistence responsibility**: `call-worker.sh` does **NOT** auto-write `sessions.json`. The host (Claude) **MUST** manually maintain `${TK_SESSION_DIR}/sessions.json` after each call: `{ worker, topic, session_id, started_at, status }`. Read sessions.json at the start of each round to find the right session_id to resume.
- **Gemini limitation**: Gemini does not print `session id:` to stderr — its `--resume` is currently unavailable. Mark `gemini_resume_unavailable: true` in `sessions.json` to avoid repeated grep attempts.
- **When NOT to resume**: scope switch (Rule 1 — restart Phase A with fresh session), context window saturation, or worker self-reports session degradation. Open a fresh session, not resume.

### Rule 3: Verify Real Data Before Writing Plans

- **Phase A plan.md MUST cite real data sources, not assumptions.** Any plan content that references existing data structures, DB schemas, API responses, model fields, or runtime behavior **MUST** be backed by one of: (a) actual DB query result, (b) reading the relevant API route / service code, (c) running a test command and observing output.
- **No "probably looks like this" speculation.** If you don't know the structure, query/read first, then write the plan. The marginal cost of one DB query or one Read is far smaller than a Phase B reviewer catching the mismatch and forcing multi-round REVISE.
- **Common failure mode**: writing a plan based on guessed shape → reviewers catch the mismatch → wasted REVISE rounds + user trust erodes. Always verify upfront.

### Rule 4: Provider-Agnostic Naming

- Pipeline names, Stage names, enum values, code paths, file/directory names, API routes, DB columns, and `entityType` identifiers **MUST** reflect the **methodology** (what the thing does), not the **provider/model** (which vendor implements it today).
- ❌ Bad: `GPT_STORYBOARD`, `gpt-storyboard/`, `seedance-pipeline`, `Stage: GPT 分镜表`, `Stage: Seedance 生视频`, `entityType: 'sora2-clip'`.
- ✅ Good: `STORYBOARD`, `storyboard/`, `reference-video-pipeline`, `Stage: 分镜表生成`, `Stage: 参考生视频`, `entityType: 'reference-video'`.
- **Self-check question**: "If we swap the model/provider tomorrow, does this name still make sense?" If no, rename before committing to it.
- **Provider locality**: record the current provider/model only in config files (`.env`, `config/providers.ts`) or runtime documentation, never in code identifiers, file paths, or DB schemas.

---

## [!MANDATORY] Session Initialization

After `/tk` is triggered, **the very first step** must be executing the following initialization. All subsequent operations depend on this result:

```bash
PROJECT_ROOT="$(git rev-parse --show-toplevel)"
TK_SESSION_DIR="${PROJECT_ROOT}/.tk-meeting/$(date +%Y%m%d-%H%M%S)"
mkdir -p "${TK_SESSION_DIR}/rounds" "${TK_SESSION_DIR}/prompts"
```

**All future references to `.tk-meeting` MUST use the `${TK_SESSION_DIR}` absolute path**. Relative paths are strictly forbidden.

Self-check output (must be printed to the user):
```
Claude: Session initialization complete
- Project Root: ${PROJECT_ROOT}
- Session Dir: ${TK_SESSION_DIR}
```

---

## Calling Workers

**[!MANDATORY] All Worker calls MUST go through the `call-worker.sh` script**. Direct CLI commands (like `codex exec ...` or `gemini "..."`) are strictly forbidden. The script handles: path absolute resolution, stderr separation, stream.log creation, and error trapping. Bypassing the script will cause missing log files and path drifting.

Call format:
```bash
bash "${PROJECT_ROOT}/.claude/skills/tk/scripts/call-worker.sh" \
  <codex|gemini> <review|implement> \
  "${TK_SESSION_DIR}/prompts/<prompt-file>.md" \
  "${TK_SESSION_DIR}/rounds/<output-file>.md" \
  [session_id]
```

Worker output is **returned as a whole block after the command finishes**.

**[!MANDATORY] When calling a Worker, you MUST use `run_in_background: true`**:
- Bash tools have a max timeout of 600000ms (10 min). Codex often exceeds 10 minutes.
- `run_in_background: true` removes the timeout limit. The system will notify you when the command completes.
- Use TaskOutput to get the result.
- **DO NOT** use `timeout: 600000` and expect the command to finish within the time limit.

**[!MANDATORY] Real-time View Guide**: Before calling a Worker, inform the user of the stderr log path and cross-platform commands:
```
Claude: Calling Codex for review. Real-time progress can be viewed by opening the file directly in your IDE (it will append in real-time), or by running in a new terminal:
  PowerShell: Get-Content -Path "${TK_SESSION_DIR}/rounds/<filename>.stderr.log" -Wait -Tail 20
  Mac/Linux:  tail -f "${TK_SESSION_DIR}/rounds/<filename>.stderr.log"
```

- `*.stderr.log` — Worker's stderr, **real-time visible in IDE** (unbuffered). Recommend opening it in the IDE.
- `*.stream.log` — Worker's complete stdout, available after the command finishes.
- You must verify that the `${TK_SESSION_DIR}` directory exists before calling.
- **Note**: Windows default terminal is PowerShell, `tail` is unavailable, `Get-Content -Wait` must be used.

For detailed CLI syntax, see [references/cli-reference.md](references/cli-reference.md).

## Communication Protocol

For the prompt format sent to Workers, attribution standards, and verdict JSON structure, see [references/communication-protocol.md](references/communication-protocol.md).

## Role Presets

For the default division of labor and system prompt templates of the three models, see [references/role-presets.md](references/role-presets.md).

---

## Full Workflow

### Phase A: User Request → Claude Drafts Plan

1. User proposes a requirement (might be vague).
2. Claude acts as a Product Manager, talking with the user to refine the requirement.
3. Claude writes the initial plan to `task-plan-prompts/<name>.md` (or a path specified by the user).
4. Claude confirms: "Initial plan complete. Ready to let Codex and Gemini review. Start review meeting?"
5. User confirms, proceeding to Phase B.

### Phase B: Joint Review (Unlimited rounds, until consensus or user stops)

Claude acts as the host, autonomously deciding routing per round:

- **Comprehensive Review**: Send to Codex first, then Gemini (attaching Codex's feedback as reference).
- **Independent Issues**: Send to the specialized model respectively, handle independently.
- **Targeted Challenge**: Forward A's challenge to B for a response.
- **Dispute Escalation**: When views conflict, use `AskUserQuestion` to ask the user to decide.
- **External Verification**: Ask Worker to check official docs and attach links.

**Convergence Condition (Three-way APPROVE Gate)**:
- **Codex APPROVE** + **Gemini APPROVE** + **Claude APPROVE** (Claude must perform independent verification, and cannot just agree because both approved).
- All three are indispensable. Only after all three APPROVE, Claude can ask the user "Ready to start implementation?"
- The user can also actively say "Enough, start implementation" to bypass the gate.

### Phase B→C Gate: Session Freshness Check

Before entering implementation, the following checks **MUST** be completed. Do not enter Phase C without completing them:

1. **Claude Self-Eval**: Assess if its own context window is too heavy.
2. **Ask Each Worker**: Ask Codex and Gemini respectively, "Is the current session still suitable to continue?"
3. **Report to User**: Format as `Claude: Session freshness check — Self-eval: [Result] / Codex: [Advice] / Gemini: [Advice] / Recommendation: [Continue / Start New]`
4. Proceed to Phase C after **User approves**.

---

### Phase C: Implementation (Execute until perfect)

**[!MANDATORY] Before each implementation step, output a self-check**:
```
Claude: [Self-Check] Ready to implement step N
- Previous step review status: ✅ APPROVE / ❌ Unreviewed / 🔄 First step
- Current session dir: ${TK_SESSION_DIR}
- Files to be modified: [List]
```

**[!MANDATORY] Core Loop (Do not skip steps)**:

```
Step N:
  1. Claude implements Step N (Read/Edit/Bash)
  2. **Immediately STOP coding** after implementation is complete.
  3. Claude **automatically initiates** Codex review (do not wait for user to hand over)
     — Use run_in_background: true
     — Inform user of stderr log path
     — Save prompt to ${TK_SESSION_DIR}/prompts/impl-step-NN-to-codex.md
  4. Wait for Codex review result
     — Save reply to ${TK_SESSION_DIR}/rounds/impl-step-NN-codex-review.md
  5. Branch based on verdict:
     ✅ APPROVE → Proceed to Step N+1
     🔄 REVISE →
       a. Claude fixes all findings
       b. Resubmit for Codex review (save as impl-step-NN-codex-review-r2.md)
       c. Loop until APPROVE (r3, r4...)
     ❌ REJECT → Escalate to user for decision
  6. If it involves Visual/UX, initiate an extra Gemini review (same loop logic as above)
```

**Micro-change Exception**: When consecutive steps are <5 lines of simple changes (e.g., config tweaks, adding comments), you can merge 2-3 steps and review them at once. When merging, you must inform the user:
```
Claude: Steps 3-5 have minimal changes (N lines total). Merging review.
```

**[!MANDATORY] Hard Constraints**:
- If Step N has not passed Codex review, **DO NOT start coding for Step N+1**.
- Claude **automatically** calls Codex for review after completing a step, do not stop and wait for user mediation.
- **FORBIDDEN** to implement multiple steps at once before initiating a review (except for the micro-change exception).
- After Codex returns REVISE, Claude MUST **automatically resubmit for review** after fixing. Do not just fix without re-reviewing.

---

## Worker Troubleshooting

When `call-worker.sh` returns a non-zero exit code or Worker output is abnormal:

1. **Check stderr log**: `cat ${TK_SESSION_DIR}/rounds/<file>.stderr.log`
2. **Common failures & handling**:
   - `command not found` → Inform user to install the corresponding CLI.
   - Process killed / no output → Check if `run_in_background: true` was missed, retry.
   - `network error` / `API error` → Wait 30 seconds and retry once.
   - 2 consecutive failures → Escalate to user, attach stderr content.
3. **Retry Strategy**: Automatically retry at most 1 time. Escalate on the 2nd failure.
4. **Fallback Plan**: If a Worker is consistently unavailable, inform the user and ask if you should proceed using only the remaining Workers.

---

## Routing Decision Principles

You autonomously decide:
- Who needs to participate in this issue (maybe just one model, maybe both).
- In what order they speak (does the latter need to see the former's feedback as a reference).
- Whether models need to talk directly (forward A's challenge to B to respond).
- When to escalate to the user and wait for a decision.
- When consensus is reached and you can proceed.

**Parallel vs Serial judgment**:
- **Parallel**: Two independent issues (e.g., backend architecture vs frontend interaction), not dependent on each other.
- **Serial**: The latter can benefit from the former's feedback (e.g., Gemini referring to Codex's conclusions during review).
- **Mandatory**: You must explain the reason to the user before every routing decision.

## Session Freshness Management

Checks **during phase transitions** (A→B, B→C) are already written into the workflow as mandatory gates and cannot be skipped.

If you feel the Worker's output quality is dropping **during the review**:
1. First ask the Worker "Is the current session still suitable to continue?"
2. Decide whether to suggest the user open a new Worker session based on the feedback.
- **NEVER automatically start a new session** — Always suggest it via Claude + await User confirmation.

---

## Runtime Directory Structure

```
${TK_SESSION_DIR}/
  plan.md                                 — Current plan (shared state)
  sessions.json                           — Session IDs for each model
  rounds/
    round-01-codex.md                     — Phase B: Codex reply
    round-01-gemini.md                    — Phase B: Gemini reply
    round-01-codex.md.stderr.log          — Phase B: Codex stderr (real-time)
    impl-step-01-codex-review.md          — Phase C: Step 1 Codex review
    impl-step-01-codex-review-r2.md       — Phase C: Re-review after fix (if any)
    impl-step-01-gemini-review.md         — Phase C: Step 1 Gemini review (if any)
    *.stderr.log                          — Real-time stderr (visible in IDE)
    *.stream.log                          — Complete stdout
  prompts/
    round-01-to-codex.md                  — Phase B: Prompt sent to Codex
    impl-step-01-to-codex.md              — Phase C: Prompt sent to Codex
```

---

## [!MANDATORY] Phase Transition Self-Check

During every phase transition, Claude **MUST output** the following self-checks (the output itself acts as an execution confirmation):

### A → B (Plan → Review)
```
Claude: [Phase Gate A→B]
- Plan file: [Path]
- Session dir: ${TK_SESSION_DIR} (Dir exists: ✅/❌)
- Sending to: [Codex/Gemini/Both]
- Routing strategy: [Serial/Parallel] + Reason
```

### B → C (Review → Implementation)
```
Claude: [Phase Gate B→C]
- Codex verdict: APPROVE ✅ / Other ❌
- Gemini verdict: APPROVE ✅ / Other ❌
- Claude independent verification: APPROVE ✅ / Other ❌
- Session freshness: Checked ✅ / Unchecked ❌
- User confirmed implementation: ✅ / ❌
```

### After each implementation step
```
Claude: [Step N Complete]
- Modified files: [List]
- Submitted for Codex review: ✅/❌
- Codex verdict: [Waiting/APPROVE/REVISE/REJECT]
- If REVISE, fixed and resubmitted: ✅/❌
- Review records saved to: ${TK_SESSION_DIR}/rounds/impl-step-NN-*
```

---

## Constraints

- **Do Not Paraphrase**: The Worker's complete output must be displayed to the user as a full block after the command completes. Do not repeatedly paraphrase or summarize it.
- **No Black Box**: Briefly explain your intent before calling a Worker (e.g., "Sending the plan to Codex for code review").
- **Do Not Overstep**: Escalate matters requiring user decisions. Do not make product decisions on behalf of the user.
- **Do Not Hardcode**: Do not preset language/framework-specific acceptance commands. Judge autonomously based on project type.
- **Attribution**: All messages MUST start with "Claude:", "Codex:", "Gemini:", or "User:".