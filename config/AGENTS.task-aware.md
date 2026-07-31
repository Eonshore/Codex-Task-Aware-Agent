<!-- BEGIN CODEX TASK-AWARE AGENT -->
## Task-aware delegation policy

Before spawning any subagent, decompose the request into independently
verifiable work items and classify each item separately.

### Difficulty routing

Classify capability first, then choose reasoning effort inside that class.
Higher effort never expands a role's permissions or substitutes for a higher
difficulty class.

- D0: Atomic, clear, and executable with one focused tool sequence.
  Do not spawn a subagent.
- D1: Deterministic extraction, classification, transformation, repetitive
  checking, or bounded read-only investigation or verification. Inputs, the
  output contract, and the success condition must be explicit, and the work
  must not require material judgment. Use `luna_task` or `luna_task_max` as
  defined under effort routing.
- D2: State-changing implementation, tool-heavy multi-step work, or bounded
  investigation and verification that requires ordinary judgment. Completion
  criteria must still be clear. Use `terra_worker` or `terra_worker_max` as
  defined under effort routing.
- D3: Ambiguous, cross-system, high-risk, security-sensitive, or architectural
  work requiring trade-off judgment. Use `sol_specialist` or
  `sol_specialist_max` as defined under effort routing.
- D4: Two or more independent D3 work items. Orchestrate them from the root,
  but keep each child bounded and non-recursive.

### Effort routing

- D1 default: call `spawn_agent` with `agent_type = "luna_task"` for compact,
  homogeneous, deterministic work.
- D1 elevated: call `spawn_agent` with `agent_type = "luna_task_max"` when the
  work remains deterministic and read-only but heterogeneous inputs, dense
  cross-checking, coverage-sensitive validation, or numerous edge cases make
  Low materially more error-prone.
- D2 default: call `spawn_agent` with `agent_type = "terra_worker"` for bounded
  implementation or investigation requiring ordinary judgment.
- D2 elevated: call `spawn_agent` with `agent_type = "terra_worker_max"` when
  the work remains D2 but coupled constraints, a long tool or verification
  chain, difficult debugging, or expensive rework justify deeper reasoning.
- D3 default: call `spawn_agent` with `agent_type = "sol_specialist"` for one
  bounded difficult decision or evidence lane.
- D3 elevated: call `spawn_agent` with `agent_type = "sol_specialist_max"` when
  both uncertainty and consequence are high, including conflicting evidence,
  security-sensitive trade-offs, irreversible architecture, adversarial edge
  cases, or a strong need to reduce reasoning variance.

Use the base effort when it is sufficient. Lower model prices reduce the
threshold for elevated effort when it is likely to improve completeness or
avoid rework, but price and task size alone are not sufficient reasons.
Capability, mutation, ambiguity, and risk determine the difficulty class before
cost is considered. Never substitute an elevated lower-class role for a higher
class.

Use Max as the single elevated effort for D1-D3. Do not add an xhigh middle lane
unless it gains a distinct routing criterion; otherwise it increases routing
ambiguity without changing the capability boundary.

`task_name` labels the child task; it does not select a custom agent.
For every D1-D3 spawn, `agent_type` is mandatory. Never omit it, and never
encode the role only in `task_name`. Before calling `spawn_agent`, verify that
the request includes the exact base or elevated `agent_type` selected above.
Always attempt the
call with `agent_type`; do not infer that it is unavailable from abbreviated
tool documentation. Only if the tool explicitly rejects `agent_type` or the
selected custom agent should the parent handle the item and report the runtime
mismatch.

### Delegation gates

Spawn a subagent only when all of the following are true:

1. Its work can proceed independently.
2. It produces a distinct deliverable or evidence lane.
3. Delegation is likely to save main-thread context or elapsed time.
4. The coordination cost is smaller than doing the work directly.

Never spawn an agent merely to restate the request, create a generic plan, or
duplicate another agent's investigation.

Do not split an atomic D0 item solely because Luna is inexpensive. Combine
adjacent microtasks that share inputs and a success contract when separate
children would not improve elapsed time, context isolation, or evidence
independence.

Use at most three direct children unless the user explicitly requests more.
Every spawn must set `fork_turns = "none"`.
The runtime configuration caps open child threads at three, excluding the
primary thread. Keep delegation at one level; children must not spawn
descendants. Do not rely on `agents.max_depth` for this boundary because Codex
V2 ignores that legacy setting. Use only one writing agent for overlapping
files or state.

### Task packet

Give every child only the minimum task packet required:

- objective;
- exact scope or paths;
- relevant constraints and evidence;
- completion condition;
- required output shape.

When selecting an elevated effort variant, also include the concrete reason the
base effort is likely to be materially more error-prone or expensive to rework.

The packet must explicitly tell the child not to delegate.
Require distilled findings instead of raw logs. If a reasonably selected
lower-cost role returns `NEEDS_ESCALATION`, escalate only with concrete
evidence. Do not route an obvious D2 or D3 item through a cheaper role merely
to obtain an escalation result.
After a spawn succeeds, the parent must not perform the same assigned work in
parallel. Wait for the child and limit parent-side checks to validating the
returned evidence and integrating the result.

When delegation occurs, briefly report the chosen difficulty and role. Do not
expose hidden reasoning or produce a long routing explanation.
<!-- END CODEX TASK-AWARE AGENT -->
