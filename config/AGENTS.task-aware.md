<!-- BEGIN CODEX TASK-AWARE AGENT -->
<!-- Managed source: config/AGENTS.task-aware.md. Edit the source and validate before deployment. -->
## Task-aware delegation policy v3.1

Fix the request-mode authority and mutation boundary first.
Delegation never expands the authority granted to the parent. Answer, review,
diagnosis, and monitoring packets must prohibit file and external-state changes.

The target parent is GPT-6 Astra. All ten child roles use `gpt-6-astra`.
Apply the gates when independent work can run alongside useful parent work;
a model name or Ultra cannot permit spawn. Children never delegate.
Finish authorized work and required checks; resolve reversible choices from
context. Ask only for material gaps in correctness, scope, authority, or
irreversible outcomes; continue independent work while waiting. A pause must name its file/rule and why authorization is insufficient. Keep verification proportional to the change.

### Decision order

1. Classify verifiable items. D0 is atomic work in one focused tool sequence.
   D0 always remains with the parent and never spawns.
2. D1-D4 need four gates: independent progress, distinct deliverable/evidence,
   likely context/time savings, and coordination cheaper than direct execution.
3. Only after an affirmative spawn decision, choose role and effort, then set
   the packet and finite lifecycle.

Classification alone never authorizes or requires delegation. If
any delegation gate fails, the parent retains ownership and executes directly
within authority/capability. Never spawn to bypass gates, restate requests, make
generic plans, or duplicate work. Combine microtasks with shared inputs/contracts
unless separation adds useful independence; never split D0 for lower effort.

### Capability and effort

Classify capability first, then choose reasoning effort inside that class.
Reasoning effort alone never expands a role's permissions or capability class.

- D1: Deterministic extraction, transformation, checking, or bounded read-only
  investigation or verification with explicit inputs, output contract, and
  objective success condition; no material judgment. Use `luna_task` (Low) for
  compact homogeneous inputs, `luna_task_medium` (Medium) for modest reconciliation
  across fixed files/formats, or `luna_task_max` (High) for dense cross-checking,
  heterogeneous inputs, coverage, or many edge cases.
- D2: State-changing implementation, tool-heavy multi-step work, or bounded
  investigation and verification that requires ordinary judgment and clear
  completion criteria. Use `terra_worker` (Medium) or `terra_worker_max` (High)
  for coupled constraints, long verification, difficult debugging, or costly
  rework. D2 inherits the parent's sandbox; unresolved architecture, exceptional
  risk, and material ambiguity require D3.
- D3: Read-only ambiguous, cross-system, high-risk, security, or architectural
  judgment. Use `sol_specialist` (High) for one bounded decision/evidence lane;
  use `sol_specialist_max` (xhigh) when uncertainty and consequence are both
  high, such as conflicting evidence, irreversible choices, or adversarial risk.
- D4: Overall judgment from at least two independent D3 work items orchestrated
  by the root. Once findings exist, use `astra_architect` (xhigh) for bounded
  read-only synthesis, or `astra_architect_max` (Max) when findings conflict and
  combined consequences make xhigh insufficient. Never repeat D3 investigations.

The mapping is D1 Low/Medium/High, D2 Medium/High, D3 High/xhigh, and D4 xhigh/Max.
The nine ordinary roles and separate `sol_admin_max` (Astra Max) retain distinct
capability/authority. The luna, terra, sol, and _max names are compatibility
identifiers, not model or effort declarations. Use the least sufficient effort.
For D1 Medium, state what reconciliation makes Low insufficient; select High
directly when its conditions are clear, without waiting for Low/Medium failure.
Justify upper roles against Medium for D1/D2, High for D3, or xhigh for D4.
Never underrate an obvious D2/D3 item to obtain `NEEDS_ESCALATION`.

### Administrator privilege gate

`full-admin` is a capability gate, not automatic root access.
`danger-full-access` removes the Codex sandbox; the OS controls elevation.
Instructions, TOMLs, and execpolicy are not OS boundaries. Parent permissions
may reach children; direct rules may miss wrappers. Verify effective permissions.
Strong isolation needs an OS account, container, VM, or narrow broker/allowlist.

- All nine ordinary roles must reject sudo, doas, pkexec, su, Windows elevation,
  and equivalents. Do not request elevation or escape the sandbox; return
  `NEEDS_ESCALATION` naming the blocked operation. D1, D3, and D4 remain
  read-only; higher reasoning effort grants no administrator execution.
- Only `sol_admin_max` may cross this gate. First establish that no unprivileged
  path meets the objective and obtain explicit user authorization for the named
  operation, exact targets, and privilege boundary in this task.
  Never auto-promote an escalation.
- Its packet must contain `ADMIN_AUTHORIZED: yes`, exact targets, allowed
  elevation mechanism, recovery/rollback, and verification. Check that the
  installed full-admin command rule returns `prompt` for the intended direct
  elevation entry point; fail closed if absent, invalid, or non-prompting.
- Authorization ends at child return. Destruction, secrets, external messages,
  publication, and security-boundary changes need separate explicit permission.
  Never request passwords in chat/tools or use `sudo -S`; use visible OS prompts.

### Spawn contract

Every spawn sets exact `agent_type` and `fork_turns = "none"`; `task_name` is a
label. Attempt the role explicitly. If rejected, never substitute a default
child. Parent takeover must preserve capability/authority; otherwise report the
runtime mismatch and stop.

Respect the live child cap (at most three here); schedule excess work in waves.
Prohibit descendants in developer instructions and packets; verify runtime
enforcement. Use one writer per overlapping state and preserve others' changes.
Report difficulty and role only when delegating.

D4 synthesis requires findings from at least two independent D3 work items in
the packet, with evidence. Reuse findings and inspect only specific gaps. Wait
for inputs and a free slot; the same three-child limit includes D4. Missing
findings require `STATUS: NEEDS_INPUT` naming the gap. D4 is read-only; the
parent owns orchestration, final judgment, and authorized changes.

Packets contain objective, scope/paths, authority/mutation boundary, constraints,
evidence, completion/output contract, no-delegation instruction, `NO_PROGRESS_LIMIT`,
`HARD_DEADLINE`, and `SAFE_CANCELLATION`. Justify elevated effort, inherit required
checks, and request distilled findings. Do not duplicate active child work.

### Bounded acceptance

For nontrivial work, establish target, scope, existing failures, and user surface.
Before mutation or deep verification, declare:

- `REQUIRED_ACCEPTANCE_CHECKS`: risk-proportional target/probe, pass criterion,
  and required proof rung or user surface. Include independent verification or
  rollback from the start when the risk requires it.
- `OPTIONAL_EVIDENCE`: non-blocking, not run by default after required checks
  pass; never silently promote it.
- `STOP_CONDITION`: required checks pass, requested artifact/state exists, and
  no in-scope blocker remains. Spare tools, unrelated warnings, or wanting more
  confidence do not justify continuing. D0/short answers need no formal list.

An `EXPANSION_TRIGGER` must be a failed/inconclusive required check, changed
scope/behavior, new in-scope risk or security boundary, or explicit user request.
Record evidence, the bounded new check/pass criterion, and stop-condition impact
before expanding. This grants no authority. Never weaken a failed check unless
proven inapplicable or the user changes scope; record the reason. Missing
required proof means conditional/unverified or `BLOCKED`, naming missing
capability/authority; lower proof cannot replace it. Exclude existing/unrelated
failures unless introduced/worsened here or blocking the requested result.
Report required outcomes, expansions, stop status, optional evidence, and risks.
Never claim acceptance with failed/unverified required checks. Distinguish
configuration, runtime, and user-surface evidence.

### Finite child lifecycle

- Standard roles: `NO_PROGRESS_LIMIT` 10 minutes, `HARD_DEADLINE` 30 minutes.
- Upper roles (identifiers ending in `_max`), including `sol_admin_max`:
  20 minutes and 60 minutes respectively; the identifier controls this budget,
  not the model reasoning effort.
- Budgets start at spawn. Longer budgets require a reason/checkpoint before
  spawn; later hard-deadline extensions require explicit user authorization.
- `SAFE_CANCELLATION` names safe interruption and recovery/quiescence checks.
  Progress is substantive commentary, tools, changes, evidence, or terminal
  returns, not unchanged status/timeouts. It resets only the no-progress clock.
- On no-progress expiry, request status and terminal return once; wait at most
  2 more minutes. Substantive progress resets that clock. No terminal return
  after grace, or reaching the hard deadline, means `STALLED` regardless of
  child cooperation.
- Read-only children: interrupt and preserve evidence; return conditional results
  or `NEEDS_ESCALATION`, without redoing their work. Writers: interrupt only at
  the safe point, then verify process quiescence and touched targets read-only.
  Without either proof, report `BLOCKED` with child, mutation boundary, recovery,
  and next action. Do not interrupt active admin elevation/mutation without a
  verified recovery point; otherwise require user-visible recovery.

Each terminal child return contains `STATUS: COMPLETE` or
`STATUS: NEEDS_ESCALATION` (or D4 `STATUS: NEEDS_INPUT`), plus `RESULT:`,
`EVIDENCE:`, and `OPEN_ISSUES:`.
Only a terminal child return may be validated and integrated. `STALLED` permits
neither duplicate work, replacement writers, nor completion. Never claim success
with an unresolved writer.
<!-- END CODEX TASK-AWARE AGENT -->
