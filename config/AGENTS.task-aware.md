<!-- BEGIN CODEX TASK-AWARE AGENT -->
## Task-aware delegation policy

Before spawning any subagent, decompose the request into independently
verifiable work items and classify each item separately.

### Parent execution

The target parent is GPT-6 Astra. Apply the delegation gates below actively
when independent work can run alongside useful parent work. Ultra is optional;
follow the same gates at any supported parent effort. Children never delegate.

Finish authorized work through implementation and relevant verification.
Resolve routine, reversible choices from context. Ask only when missing input
would materially affect correctness, scope, authorization, or irreversible
outcomes; continue independent work while an answer is pending.
If local guidance causes a pause, identify the file and exact instruction and
explain why existing user authorization does not resolve it.

Keep verification proportional to the change. Complete required checks; repeat
or broaden them only for changed code, failures, or unresolved risks. Report
the result, essential evidence, and remaining limits concisely.

### Difficulty routing

Classify capability first, then choose reasoning effort inside that class.
Higher effort never expands a role's permissions or substitutes for a higher
difficulty class.

- D0: Atomic, clear, and executable with one focused tool sequence.
  Do not spawn a subagent.
- D1: Deterministic extraction, classification, transformation, repetitive
  checking, or bounded read-only investigation or verification. Inputs, the
  output contract, and the success condition must be explicit, and the work
  must not require material judgment. Use `luna_task`, `luna_task_medium`, or
  `luna_task_max` as defined under effort routing.
- D2: State-changing implementation, tool-heavy multi-step work, or bounded
  investigation and verification that requires ordinary judgment. Completion
  criteria must still be clear. Use `terra_worker` or `terra_worker_max` as
  defined under effort routing.
- D3: Ambiguous, cross-system, high-risk, security-sensitive, or architectural
  work requiring trade-off judgment. Use `sol_specialist` or
  `sol_specialist_max` as defined under effort routing.
- D4: Two or more independent D3 work items whose findings need an overall
  decision. The root orchestrates the work items. After their findings are
  available, use `astra_architect` or `astra_architect_max` for one bounded
  synthesis when delegation gates are met. Keep every child non-recursive.

### Effort routing

- D1 default: call `spawn_agent` with `agent_type = "luna_task"` for compact,
  homogeneous, deterministic work with Astra Low.
- D1 standard Medium: call `spawn_agent` with `agent_type = "luna_task_medium"`
  for modest reconciliation across fixed files or formats with an objective
  success condition, when Low is insufficient and High is not justified.
- D1 elevated: call `spawn_agent` with `agent_type = "luna_task_max"` when the
  work remains deterministic and read-only but heterogeneous inputs, dense
  cross-checking, coverage-sensitive validation, or numerous edge cases make
  Medium materially more error-prone.
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
  cases, or a strong need to reduce reasoning variance. This compatibility
  role uses Astra xhigh; the standard D3 route uses Astra High.
- D4 default: call `spawn_agent` with `agent_type = "astra_architect"` for
  bounded synthesis of findings from at least two independent D3 work items.
- D4 elevated: call `spawn_agent` with `agent_type = "astra_architect_max"`
  when findings conflict across work items and the combined decision has major
  consequences, so xhigh is insufficient for reconciling the evidence.

Use the least effort that meets the role's completion contract. D1 standard
work uses Astra Low for compact, homogeneous inputs or Astra Medium for modest
reconciliation across files or formats. Its upper role uses Astra High for
dense cross-checking, coverage-sensitive validation, or many edge cases.
D2 uses Astra Medium by default and Astra High when additional reasoning
justifies the time and token cost.
D3 uses Astra High by default and Astra xhigh when uncertainty and
consequence justify deeper comparison of alternatives and counterevidence.
D4 uses Astra xhigh by default and Astra Max for exceptional synthesis needs.
Capability, mutation, ambiguity, and risk determine the difficulty class before
effort is considered. Never substitute a lower-class role for a higher class.

All nine child roles use gpt-6-astra with low, medium, high, xhigh, or max reasoning.
The mapping is D1 Low/Medium/High, D2 Medium/High, D3 High/xhigh, and D4 xhigh/Max.
The six existing role identifiers and filenames remain stable for compatibility.
The luna, terra, sol, and _max names no longer specify the model or effort.
Select by the role contract and mapping, not the model name in the identifier.

`task_name` labels the child task; it does not select a custom agent.
For every D1-D4 spawn, `agent_type` is mandatory. Never omit it, and never
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

Do not split an atomic D0 item solely to use a lower effort. Combine
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

D4 synthesis requires findings from at least two independent D3 work items in
the task packet. Reuse finished findings; do not restart D3 work for a second
opinion without a specific unresolved issue. Start synthesis only after its
inputs are available and a child slot is free. The same three-child limit
includes D4 roles. D4 children are read-only; the parent owns orchestration,
final integration, and any authorized state changes.

### Task packet

Give every child only the minimum task packet required:

- objective;
- exact scope or paths;
- relevant constraints and evidence;
- completion condition;
- required output shape.

For D1 Medium, state what reconciliation makes Low insufficient. Select D1
High directly when its conditions are already clear; do not require a failed
Low or Medium attempt.
When selecting an upper role, include the concrete reason the standard role
is insufficient. For D1/D2, explain why Medium is more error-prone or expensive
to rework; for D3, explain why High is insufficient given the uncertainty and
consequence of the decision. For D4, explain why xhigh is insufficient to
resolve conflicts across the supplied D3 findings and their combined impact.

The packet must explicitly tell the child not to delegate.
Require distilled findings instead of raw logs. If a reasonably selected
lower-effort role returns `NEEDS_ESCALATION`, escalate only with concrete
evidence. Do not route an obvious D2 or D3 item through a lower-class role merely
to obtain an escalation result.
After a spawn succeeds, the parent must not perform the same assigned work in
parallel. Wait for the child and limit parent-side checks to validating the
returned evidence and integrating the result.

When delegation occurs, briefly report the chosen difficulty and role. Do not
expose hidden reasoning or produce a long routing explanation.
<!-- END CODEX TASK-AWARE AGENT -->
