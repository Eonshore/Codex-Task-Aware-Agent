#!/usr/bin/env bash

set -Eeuo pipefail

usage() {
    cat <<'EOF'
Usage: test-task-aware-agent.sh [OPTIONS]

Validate an installed Codex Task-Aware Agent configuration.

Options:
  --codex-home PATH  Target Codex home (default: $CODEX_HOME or ~/.codex)
  --skip-runtime     Skip the codex execpolicy and doctor checks
  --config-only-runtime
                      Require strict config loading but ignore unrelated doctor failures
  -h, --help         Show this help
EOF
}

codex_home="${CODEX_HOME:-$HOME/.codex}"
skip_runtime=false
config_only_runtime=false

while (($# > 0)); do
    case "$1" in
        --codex-home)
            (($# >= 2)) || { printf '%s\n' 'Error: --codex-home requires a path' >&2; exit 1; }
            codex_home=$2
            shift 2
            ;;
        --skip-runtime)
            skip_runtime=true
            shift
            ;;
        --config-only-runtime)
            config_only_runtime=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'Error: unknown option: %s\n' "$1" >&2
            exit 1
            ;;
    esac
done

failures=0
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repository_root=$(cd -- "$script_dir/.." && pwd -P)
source_policy_path="$repository_root/config/AGENTS.task-aware.md"
agents_source="$repository_root/agents"
rules_source="$repository_root/rules/full-admin.rules"
config_path="$codex_home/config.toml"
agents_md_path="$codex_home/AGENTS.md"
agents_path="$codex_home/agents"
full_admin_rule_path="$codex_home/rules/task-aware-full-admin.rules"

record_failure() {
    printf '%s\n' "$*" >&2
    failures=$((failures + 1))
}

assert_file_contains() {
    local path=$1
    shift

    if [[ ! -f "$path" ]]; then
        record_failure "Missing file: $path"
        return
    fi

    local pattern
    for pattern in "$@"; do
        if ! grep -Eq -- "$pattern" "$path"; then
            record_failure "Missing pattern '$pattern' in $path"
        fi
    done
}

assert_file_absent() {
    local path=$1
    if [[ -e "$path" ]]; then
        record_failure "Unexpected retired file: $path"
    fi
}

assert_file_byte_parity() {
    local source_path=$1
    local installed_path=$2
    local label=$3

    if [[ ! -f "$source_path" ]]; then
        record_failure "Missing $label source: $source_path"
    elif [[ ! -f "$installed_path" ]]; then
        record_failure "Missing installed $label: $installed_path"
    elif ! cmp -s -- "$source_path" "$installed_path"; then
        record_failure "Installed $label does not match source bytes: $label"
    fi
}

count_exact_marker() {
    local path=$1
    local marker=$2

    LC_ALL=C awk -v marker="$marker" '
        {
            line = $0
            sub(/\r$/, "", line)
            if (line == marker) {
                count += 1
            }
        }
        END { print count + 0 }
    ' "$path"
}

has_one_ordered_marker_pair() {
    local path=$1
    local begin_marker='<!-- BEGIN CODEX TASK-AWARE AGENT -->'
    local end_marker='<!-- END CODEX TASK-AWARE AGENT -->'

    LC_ALL=C awk -v begin_marker="$begin_marker" -v end_marker="$end_marker" '
        {
            line = $0
            sub(/\r$/, "", line)
            if (line == begin_marker) {
                begin_count += 1
                if (end_count > 0 || begin_count != 1) invalid = 1
            } else if (line == end_marker) {
                end_count += 1
                if (begin_count != 1 || end_count != 1) invalid = 1
            }
        }
        END { exit !(begin_count == 1 && end_count == 1 && !invalid) }
    ' "$path"
}

extract_managed_policy_block() {
    local path=$1
    local begin_marker='<!-- BEGIN CODEX TASK-AWARE AGENT -->'
    local end_marker='<!-- END CODEX TASK-AWARE AGENT -->'

    LC_ALL=C awk -v begin_marker="$begin_marker" -v end_marker="$end_marker" '
        {
            line = $0
            sub(/\r$/, "", line)
            if (line == begin_marker) {
                begin_count += 1
                if (end_count > 0 || begin_count != 1) invalid = 1
                if (begin_count == 1 && end_count == 0) emitting = 1
            }
            if (emitting) print $0
            if (line == end_marker) {
                end_count += 1
                if (begin_count != 1 || !emitting || end_count != 1) invalid = 1
                if (emitting) {
                    emitting = 0
                    completed = 1
                }
            }
        }
        END { exit !(begin_count == 1 && end_count == 1 && completed && !invalid) }
    ' "$path"
}

assert_managed_policy_parity() {
    local source_path=$1
    local installed_path=$2
    local begin_marker='<!-- BEGIN CODEX TASK-AWARE AGENT -->'
    local end_marker='<!-- END CODEX TASK-AWARE AGENT -->'
    local path begin_count end_count valid=true

    for path in "$source_path" "$installed_path"; do
        if [[ ! -f "$path" ]]; then
            record_failure "Missing managed policy file: $path"
            valid=false
            continue
        fi
        begin_count=$(count_exact_marker "$path" "$begin_marker")
        end_count=$(count_exact_marker "$path" "$end_marker")
        if [[ "$begin_count" != 1 || "$end_count" != 1 ]]; then
            record_failure "Expected exactly one managed marker pair in $path; found begin=$begin_count end=$end_count."
            valid=false
        fi
        if ! has_one_ordered_marker_pair "$path"; then
            record_failure "Managed markers are not one ordered begin/end pair in $path."
            valid=false
        fi
    done

    if [[ "$valid" == true ]] && ! cmp -s -- "$source_path" <(extract_managed_policy_block "$installed_path"); then
        record_failure 'Managed Task-Aware policy source/live byte parity failed.'
    fi
}

managed_block_matches_patterns() {
    local block=$1
    shift

    local pattern
    for pattern in "$@"; do
        if ! grep -Eq -- "$pattern" <<< "$block"; then
            return 1
        fi
    done
    return 0
}

managed_block_has_no_patterns() {
    local block=$1
    shift

    local pattern
    for pattern in "$@"; do
        if grep -Eq -- "$pattern" <<< "$block"; then
            return 1
        fi
    done
    return 0
}

assert_managed_policy_patterns() {
    local path=$1
    shift
    local block

    if [[ ! -f "$path" ]]; then
        record_failure "Missing managed policy file: $path"
        return
    fi
    if ! block=$(extract_managed_policy_block "$path"); then
        record_failure "Could not extract one ordered managed marker pair from $path."
        return
    fi

    local pattern
    for pattern in "$@"; do
        if ! grep -Eq -- "$pattern" <<< "$block"; then
            record_failure "Missing managed pattern '$pattern' in $path"
        fi
    done
}

assert_managed_policy_excludes() {
    local path=$1
    shift
    local block

    if [[ ! -f "$path" ]]; then
        record_failure "Missing managed policy file: $path"
        return
    fi
    if ! block=$(extract_managed_policy_block "$path"); then
        record_failure "Could not extract one ordered managed marker pair from $path."
        return
    fi

    local pattern
    for pattern in "$@"; do
        if grep -Eq -- "$pattern" <<< "$block"; then
            record_failure "Forbidden managed pattern '$pattern' found in $path"
        fi
    done
}

run_policy_fault_injection() {
    local source_block without_deadline without_stalled without_classification
    local without_required without_optional without_stop with_legacy_wait

    if ! source_block=$(extract_managed_policy_block "$source_policy_path"); then
        record_failure 'Could not extract source policy for fault injection.'
        return
    fi
    if ! managed_block_matches_patterns "$source_block" "${managed_policy_patterns[@]}" ||
        ! managed_block_has_no_patterns "$source_block" "${forbidden_policy_patterns[@]}"; then
        record_failure 'Source policy does not satisfy the managed policy contract before fault injection.'
        return
    fi

    without_deadline=${source_block//HARD_DEADLINE/DEADLINE_REMOVED}
    if managed_block_matches_patterns "$without_deadline" "${managed_policy_patterns[@]}"; then
        record_failure 'Fault injection did not detect removed HARD_DEADLINE clauses.'
    fi
    without_stalled=${source_block//STALLED/LIFECYCLE_STOPPED}
    if managed_block_matches_patterns "$without_stalled" "${managed_policy_patterns[@]}"; then
        record_failure 'Fault injection did not detect removed STALLED clauses.'
    fi
    without_classification=${source_block//Classification alone never authorizes or requires delegation/Classification authorization removed}
    if managed_block_matches_patterns "$without_classification" "${managed_policy_patterns[@]}"; then
        record_failure 'Fault injection did not detect removed classification-not-authorization clause.'
    fi
    without_required=${source_block//REQUIRED_ACCEPTANCE_CHECKS/REQUIRED_CHECKS_REMOVED}
    if managed_block_matches_patterns "$without_required" "${managed_policy_patterns[@]}"; then
        record_failure 'Fault injection did not detect removed REQUIRED_ACCEPTANCE_CHECKS clauses.'
    fi
    without_optional=${source_block//OPTIONAL_EVIDENCE/OPTIONAL_REMOVED}
    if managed_block_matches_patterns "$without_optional" "${managed_policy_patterns[@]}"; then
        record_failure 'Fault injection did not detect removed OPTIONAL_EVIDENCE clauses.'
    fi
    without_stop=${source_block//STOP_CONDITION/STOP_REMOVED}
    if managed_block_matches_patterns "$without_stop" "${managed_policy_patterns[@]}"; then
        record_failure 'Fault injection did not detect removed STOP_CONDITION clauses.'
    fi
    with_legacy_wait="$source_block"$'\n''a tool-wait timeout is nonterminal: re-wait and do not interrupt'
    if managed_block_has_no_patterns "$with_legacy_wait" "${forbidden_policy_patterns[@]}"; then
        record_failure 'Fault injection did not reject the unbounded wait clause.'
    fi
}

assert_file_contains "$config_path" \
    '^[[:space:]]*\[agents\][[:space:]]*(#.*)?$' \
    '^enabled[[:space:]]*=[[:space:]]*true[[:space:]]*$' \
    '^max_concurrent_threads_per_session[[:space:]]*=[[:space:]]*3[[:space:]]*$'

assert_managed_policy_parity "$source_policy_path" "$agents_md_path"

# Keep always-loaded guidance compact; do not cap the user's unmanaged text.
if [[ -f "$source_policy_path" ]] && (( $(wc -c < "$source_policy_path") > 10240 )); then
    record_failure 'Managed policy exceeds the 10 KiB maintenance budget; consolidate existing rules before adding more.'
fi

managed_policy_patterns=(
    'Managed source: config/AGENTS\.task-aware\.md'
    'Task-aware delegation policy v3\.1'
    'Fix the request-mode authority and mutation boundary'
    'Delegation never expands the authority granted to the parent'
    'D1 uses `gpt-6-luna`, D2 uses `gpt-6-sol`'
    'The target parent is GPT-6 Astra'
    'D3/D4 use `gpt-6-astra`'
    'Children never delegate'
    'Classify capability first, then choose reasoning effort'
    'luna_task_medium'
    'astra_architect'
    'astra_architect_max'
    'D1 Low/Medium/High, D2 Medium/High, D3 High/xhigh, and D4 xhigh/Max'
    'D4 synthesis requires findings from at least two independent D3 work items'
    'same three-child limit'
    'NEEDS_INPUT'
    '### Decision order'
    'D0 always remains with the parent and never spawns'
    'Only after an affirmative spawn decision, choose role and effort'
    'Classification alone never authorizes or requires delegation'
    'any delegation gate fails, the parent retains ownership and executes directly'
    'Reasoning effort alone never expands a role'\''s permissions'
    'Administrator privilege gate'
    'ADMIN_AUTHORIZED: yes'
    'Never auto-promote an escalation'
    'REQUIRED_ACCEPTANCE_CHECKS'
    'OPTIONAL_EVIDENCE'
    'STOP_CONDITION'
    'EXPANSION_TRIGGER'
    'NO_PROGRESS_LIMIT'
    'HARD_DEADLINE'
    'SAFE_CANCELLATION'
    'Upper roles'
    'STALLED'
    'Only a terminal child return may be validated and integrated'
)
forbidden_policy_patterns=(
    'tool-wait timeout is nonterminal: re-wait and do not interrupt'
    'After required checks pass, continue collecting any additional evidence available'
    'D1 default: call `spawn_agent`'
)

assert_managed_policy_patterns "$source_policy_path" "${managed_policy_patterns[@]}"
assert_managed_policy_patterns "$agents_md_path" "${managed_policy_patterns[@]}"
assert_managed_policy_excludes "$source_policy_path" "${forbidden_policy_patterns[@]}"
assert_managed_policy_excludes "$agents_md_path" "${forbidden_policy_patterns[@]}"
run_policy_fault_injection

expected_agent_specs=(
    'luna-task.toml|luna_task|gpt-6-luna|low|read-only|never'
    'luna-task-medium.toml|luna_task_medium|gpt-6-luna|medium|read-only|never'
    'luna-task-max.toml|luna_task_max|gpt-6-luna|high|read-only|never'
    'terra-worker.toml|terra_worker|gpt-6-sol|medium||never'
    'terra-worker-max.toml|terra_worker_max|gpt-6-sol|high||never'
    'sol-specialist.toml|sol_specialist|gpt-6-astra|high|read-only|never'
    'sol-specialist-max.toml|sol_specialist_max|gpt-6-astra|xhigh|read-only|never'
    'astra-architect.toml|astra_architect|gpt-6-astra|xhigh|read-only|never'
    'astra-architect-max.toml|astra_architect_max|gpt-6-astra|max|read-only|never'
    'sol-admin-max.toml|sol_admin_max|gpt-6-astra|max|danger-full-access|on-request'
)

for spec in "${expected_agent_specs[@]}"; do
    IFS='|' read -r agent_file agent_name agent_model agent_effort agent_sandbox agent_approval <<< "$spec"
    installed_agent_path="$agents_path/$agent_file"
    source_agent_path="$agents_source/$agent_file"
    assert_file_contains "$installed_agent_path" \
        "^name[[:space:]]*=[[:space:]]*\"$agent_name\"[[:space:]]*$" \
        '^description[[:space:]]*=[[:space:]]*"""' \
        '^developer_instructions[[:space:]]*=[[:space:]]*"""' \
        "^model[[:space:]]*=[[:space:]]*\"$agent_model\"[[:space:]]*$" \
        "^model_reasoning_effort[[:space:]]*=[[:space:]]*\"$agent_effort\"[[:space:]]*$" \
        "^approval_policy[[:space:]]*=[[:space:]]*\"$agent_approval\"[[:space:]]*$"
    if [[ -n "$agent_sandbox" ]]; then
        assert_file_contains "$installed_agent_path" "^sandbox_mode[[:space:]]*=[[:space:]]*\"$agent_sandbox\"[[:space:]]*$"
    elif [[ -f "$installed_agent_path" ]] && grep -Eq '^[[:space:]]*sandbox_mode[[:space:]]*=' "$installed_agent_path"; then
        record_failure "D2 role must inherit the parent sandbox: $agent_file"
    fi
    assert_file_byte_parity "$source_agent_path" "$installed_agent_path" "agent $agent_file"
done

for agent_file in luna-task.toml luna-task-medium.toml luna-task-max.toml terra-worker.toml terra-worker-max.toml sol-specialist.toml sol-specialist-max.toml astra-architect.toml astra-architect-max.toml; do
    assert_file_contains "$agents_path/$agent_file" 'Never invoke or request sudo'
done
# Retain the GPT-6 family role capability contracts.
assert_file_contains "$agents_path/luna-task.toml" \
    '^name[[:space:]]*=[[:space:]]*"luna_task"[[:space:]]*$' \
    '^description[[:space:]]*=[[:space:]]*"""' \
    '^developer_instructions[[:space:]]*=[[:space:]]*"""' \
    '^model[[:space:]]*=[[:space:]]*"gpt-6-luna"[[:space:]]*$' \
    '^model_reasoning_effort[[:space:]]*=[[:space:]]*"low"[[:space:]]*$' \
    '^sandbox_mode[[:space:]]*=[[:space:]]*"read-only"[[:space:]]*$' \
    'Use as the default for compact, homogeneous D1' \
    'bounded read-only investigation or' \
    'fixed inputs, an explicit output contract' \
    'success condition' \
    'Do not use for material judgment, broad investigation, or state changes'

assert_file_contains "$agents_path/luna-task-medium.toml" \
    '^name[[:space:]]*=[[:space:]]*"luna_task_medium"[[:space:]]*$' \
    '^description[[:space:]]*=[[:space:]]*"""' \
    '^developer_instructions[[:space:]]*=[[:space:]]*"""' \
    '^model[[:space:]]*=[[:space:]]*"gpt-6-luna"[[:space:]]*$' \
    '^model_reasoning_effort[[:space:]]*=[[:space:]]*"medium"[[:space:]]*$' \
    '^sandbox_mode[[:space:]]*=[[:space:]]*"read-only"[[:space:]]*$' \
    'bounded D1 work with fixed inputs' \
    'modest reconciliation across files or' \
    'objective success condition' \
    'Do not use for material judgment, broad investigation, or state changes' \
    'Do not broaden scope or delegate'

assert_file_contains "$agents_path/luna-task-max.toml" \
    '^name[[:space:]]*=[[:space:]]*"luna_task_max"[[:space:]]*$' \
    '^description[[:space:]]*=[[:space:]]*"""' \
    '^developer_instructions[[:space:]]*=[[:space:]]*"""' \
    '^model[[:space:]]*=[[:space:]]*"gpt-6-luna"[[:space:]]*$' \
    '^model_reasoning_effort[[:space:]]*=[[:space:]]*"high"[[:space:]]*$' \
    '^sandbox_mode[[:space:]]*=[[:space:]]*"read-only"[[:space:]]*$' \
    'D1 work that remains deterministic, read-only, and objectively' \
    'dense cross-checking across heterogeneous inputs' \
    'Do not use for material judgment, broad investigation, or state changes' \
    'Use High reasoning for completeness and cross-checking' \
    "not to broaden the task's" \
    'capability boundary'

assert_file_contains "$agents_path/terra-worker.toml" \
    '^name[[:space:]]*=[[:space:]]*"terra_worker"[[:space:]]*$' \
    '^description[[:space:]]*=[[:space:]]*"""' \
    '^developer_instructions[[:space:]]*=[[:space:]]*"""' \
    'Use as the default for bounded D2 state-changing implementation' \
    'tool-heavy' \
    'multi-step work' \
    'requires ordinary' \
    'judgment while keeping clear success criteria' \
    '^model[[:space:]]*=[[:space:]]*"gpt-6-sol"[[:space:]]*$' \
    '^model_reasoning_effort[[:space:]]*=[[:space:]]*"medium"[[:space:]]*$'

assert_file_contains "$agents_path/terra-worker-max.toml" \
    '^name[[:space:]]*=[[:space:]]*"terra_worker_max"[[:space:]]*$' \
    '^description[[:space:]]*=[[:space:]]*"""' \
    '^developer_instructions[[:space:]]*=[[:space:]]*"""' \
    'D2 work that stays within ordinary engineering judgment' \
    'many' \
    'coupled constraints' \
    'Do not use for unresolved architectural trade-offs' \
    'Use High reasoning for coupled constraints, edge cases, and verification' \
    'not to' \
    "broaden the task's capability boundary" \
    '^model[[:space:]]*=[[:space:]]*"gpt-6-sol"[[:space:]]*$' \
    '^model_reasoning_effort[[:space:]]*=[[:space:]]*"high"[[:space:]]*$'

assert_file_contains "$agents_path/sol-specialist.toml" \
    '^name[[:space:]]*=[[:space:]]*"sol_specialist"[[:space:]]*$' \
    '^description[[:space:]]*=[[:space:]]*"""' \
    '^developer_instructions[[:space:]]*=[[:space:]]*"""' \
    '^model[[:space:]]*=[[:space:]]*"gpt-6-astra"[[:space:]]*$' \
    '^model_reasoning_effort[[:space:]]*=[[:space:]]*"high"[[:space:]]*$' \
    '^sandbox_mode[[:space:]]*=[[:space:]]*"read-only"[[:space:]]*$' \
    'Use as the default for one bounded D3' \
    'Prefer sol_specialist_max when uncertainty and consequence are both'

assert_file_contains "$agents_path/sol-specialist-max.toml" \
    '^name[[:space:]]*=[[:space:]]*"sol_specialist_max"[[:space:]]*$' \
    '^description[[:space:]]*=[[:space:]]*"""' \
    '^developer_instructions[[:space:]]*=[[:space:]]*"""' \
    'D3 work when both uncertainty and consequence are high' \
    'security-sensitive trade-offs' \
    'reasoning variance' \
    '^model[[:space:]]*=[[:space:]]*"gpt-6-astra"[[:space:]]*$' \
    '^model_reasoning_effort[[:space:]]*=[[:space:]]*"xhigh"[[:space:]]*$' \
    '^sandbox_mode[[:space:]]*=[[:space:]]*"read-only"[[:space:]]*$'

assert_file_contains "$agents_path/astra-architect.toml" \
    '^name[[:space:]]*=[[:space:]]*"astra_architect"[[:space:]]*$' \
    '^description[[:space:]]*=[[:space:]]*"""' \
    '^developer_instructions[[:space:]]*=[[:space:]]*"""' \
    '^model[[:space:]]*=[[:space:]]*"gpt-6-astra"[[:space:]]*$' \
    '^model_reasoning_effort[[:space:]]*=[[:space:]]*"xhigh"[[:space:]]*$' \
    '^sandbox_mode[[:space:]]*=[[:space:]]*"read-only"[[:space:]]*$' \
    'bounded D4 synthesis' \
    'at least two independent D3' \
    'read-only synthesis role; the parent owns orchestration' \
    'NEEDS_INPUT' \
    'Do not repeat completed investigations' \
    'Do not delegate' \
    'Do not modify files or external state'

assert_file_contains "$agents_path/astra-architect-max.toml" \
    '^name[[:space:]]*=[[:space:]]*"astra_architect_max"[[:space:]]*$' \
    '^description[[:space:]]*=[[:space:]]*"""' \
    '^developer_instructions[[:space:]]*=[[:space:]]*"""' \
    '^model[[:space:]]*=[[:space:]]*"gpt-6-astra"[[:space:]]*$' \
    '^model_reasoning_effort[[:space:]]*=[[:space:]]*"max"[[:space:]]*$' \
    '^sandbox_mode[[:space:]]*=[[:space:]]*"read-only"[[:space:]]*$' \
    'bounded D4 synthesis' \
    'at least two independent D3' \
    'read-only synthesis role; the parent owns orchestration' \
    'NEEDS_INPUT' \
    'Do not repeat completed investigations' \
    'Do not delegate' \
    'Do not modify files or external state'

assert_file_contains "$agents_path/sol-admin-max.toml" \
    'ADMIN_AUTHORIZED: yes' \
    'Before every command that uses sudo' \
    'never use sudo -S' \
    'This role definition alone is not root or an administrator token'

assert_file_contains "$full_admin_rule_path" \
    'decision[[:space:]]*=[[:space:]]*"prompt"' \
    '"sudo"' \
    '"doas"' \
    '"pkexec"' \
    '"su"' \
    '"runas"' \
    '"gsudo"' \
    '"Start-Process"' \
    'explicit sol_admin_max full-admin gate'
assert_file_byte_parity "$rules_source" "$full_admin_rule_path" 'full-admin rule'

assert_file_absent "$agents_path/luna-task-high.toml"
assert_file_absent "$agents_path/terra-worker-high.toml"

if ((failures > 0)); then
    printf 'Task-Aware Agent validation failed with %d error(s).\n' "$failures" >&2
    exit 1
fi

if [[ "$skip_runtime" == false ]]; then
    if command -v codex >/dev/null 2>&1; then
        set +e
        execpolicy_output=$(CODEX_HOME="$codex_home" codex execpolicy check --pretty --rules "$full_admin_rule_path" -- sudo -n true 2>&1)
        execpolicy_exit=$?
        set -e
        if ((execpolicy_exit != 0)) || ! grep -Eq '"decision"[[:space:]]*:[[:space:]]*"prompt"' <<< "$execpolicy_output"; then
            printf '%s\n' "$execpolicy_output" >&2
            printf 'Full-admin execpolicy did not return prompt for harmless sudo text (exit %d).\n' "$execpolicy_exit" >&2
            exit 1
        fi
        printf 'Full-admin execpolicy prompt passed for CODEX_HOME=%s.\n' "$codex_home"

        if [[ "$config_only_runtime" == true ]]; then
            set +e
            doctor_output=$(CODEX_HOME="$codex_home" codex --strict-config doctor --json --no-color 2>&1)
            doctor_exit=$?
            set -e
            config_status=$(awk '
                /"config.load"[[:space:]]*:/ { in_config = 1 }
                in_config && /"status"[[:space:]]*:/ {
                    status = $0
                    sub(/^.*"status"[[:space:]]*:[[:space:]]*"/, "", status)
                    sub(/".*$/, "", status)
                    print status
                    exit
                }
            ' <<< "$doctor_output")
            if [[ "$config_status" != ok ]]; then
                printf '%s\n' "$doctor_output" >&2
                printf 'Codex strict config load failed with doctor exit %d for CODEX_HOME=%s.\n' "$doctor_exit" "$codex_home" >&2
                exit 1
            fi
            printf 'Codex strict config load passed for CODEX_HOME=%s.\n' "$codex_home"
        else
            CODEX_HOME="$codex_home" codex --strict-config doctor --summary --no-color --ascii
        fi
    else
        printf '%s\n' 'Warning: codex was not found; file validation passed but runtime validation was skipped.' >&2
    fi
fi

printf '%s\n' 'Task-Aware Agent validation passed.'
