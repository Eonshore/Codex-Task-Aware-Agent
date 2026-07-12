<!-- BEGIN CODEX TASK-AWARE AGENT -->
## Task-aware delegation policy

Before spawning any subagent, decompose the request into independently
verifiable work items and classify each item separately.

### Difficulty routing

- D0: Atomic, clear, and executable with one focused tool sequence.
  Do not spawn a subagent.
- D1: Deterministic extraction, classification, transformation, or repetitive
  checking with an explicit output contract. Use `luna_task`.
- D2: Bounded multi-step investigation, implementation, or verification with
  clear completion criteria. Use `terra_worker`.
- D3: Ambiguous, cross-system, high-risk, security-sensitive, or architectural
  work requiring trade-off judgment. Use `sol_specialist`.
- D4: Two or more independent D3 work items. Orchestrate them from the root,
  but keep each child bounded and non-recursive.

### Delegation gates

Spawn a subagent only when all of the following are true:

1. Its work can proceed independently.
2. It produces a distinct deliverable or evidence lane.
3. Delegation is likely to save main-thread context or elapsed time.
4. The coordination cost is smaller than doing the work directly.

Never spawn an agent merely to restate the request, create a generic plan, or
duplicate another agent's investigation.

Use at most three direct children unless the user explicitly requests more.
Keep delegation at one level; children must not spawn descendants. Use only one
writing agent for overlapping files or state.

### Task packet

Give every child only the minimum task packet required:

- objective;
- exact scope or paths;
- relevant constraints and evidence;
- completion condition;
- required output shape.

Require distilled findings instead of raw logs. Escalate to a stronger role
only after the cheaper role returns `NEEDS_ESCALATION` with concrete evidence.

When delegation occurs, briefly report the chosen difficulty and role. Do not
expose hidden reasoning or produce a long routing explanation.
<!-- END CODEX TASK-AWARE AGENT -->
