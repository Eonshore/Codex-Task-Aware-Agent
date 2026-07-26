#!/usr/bin/env bash

set -Eeuo pipefail

usage() {
    cat <<'EOF'
Usage: test-task-aware-agent.sh [OPTIONS]

Validate an installed Codex Task-Aware Agent configuration.

Options:
  --codex-home PATH  Target Codex home (default: $CODEX_HOME or ~/.codex)
  --skip-runtime     Skip the codex doctor runtime check
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
            if (($# < 2)); then
                printf 'Error: --codex-home requires a path\n' >&2
                exit 1
            fi
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

assert_file_contains() {
    local path=$1
    shift

    if [[ ! -f "$path" ]]; then
        printf 'Missing file: %s\n' "$path" >&2
        failures=$((failures + 1))
        return
    fi

    local pattern
    for pattern in "$@"; do
        if ! grep -Eq -- "$pattern" "$path"; then
            printf "Missing pattern '%s' in %s\n" "$pattern" "$path" >&2
            failures=$((failures + 1))
        fi
    done
}

config_path="$codex_home/config.toml"
agents_md_path="$codex_home/AGENTS.md"
agents_path="$codex_home/agents"

assert_file_contains "$config_path" \
    '^[[:space:]]*\[agents\][[:space:]]*(#.*)?$' \
    '^enabled[[:space:]]*=[[:space:]]*true[[:space:]]*$' \
    '^max_concurrent_threads_per_session[[:space:]]*=[[:space:]]*3[[:space:]]*$'

assert_file_contains "$agents_md_path" \
    '<!-- BEGIN CODEX TASK-AWARE AGENT -->' \
    'Task-aware delegation policy' \
    'agent_type[[:space:]]*=[[:space:]]*"luna_task"' \
    'agent_type[[:space:]]*=[[:space:]]*"terra_worker"' \
    'agent_type[[:space:]]*=[[:space:]]*"sol_specialist"' \
    'fork_turns[[:space:]]*=[[:space:]]*"none"' \
    'packet must explicitly tell the child not to delegate' \
    '<!-- END CODEX TASK-AWARE AGENT -->'

assert_file_contains "$agents_path/luna-task.toml" \
    '^name[[:space:]]*=[[:space:]]*"[^"]+"[[:space:]]*$' \
    '^description[[:space:]]*=[[:space:]]*"""' \
    '^developer_instructions[[:space:]]*=[[:space:]]*"""' \
    '^model[[:space:]]*=[[:space:]]*"gpt-5\.6-luna"[[:space:]]*$' \
    '^model_reasoning_effort[[:space:]]*=[[:space:]]*"low"[[:space:]]*$' \
    '^sandbox_mode[[:space:]]*=[[:space:]]*"read-only"[[:space:]]*$'

assert_file_contains "$agents_path/terra-worker.toml" \
    '^name[[:space:]]*=[[:space:]]*"[^"]+"[[:space:]]*$' \
    '^description[[:space:]]*=[[:space:]]*"""' \
    '^developer_instructions[[:space:]]*=[[:space:]]*"""' \
    '^model[[:space:]]*=[[:space:]]*"gpt-5\.6-terra"[[:space:]]*$' \
    '^model_reasoning_effort[[:space:]]*=[[:space:]]*"medium"[[:space:]]*$'

assert_file_contains "$agents_path/sol-specialist.toml" \
    '^name[[:space:]]*=[[:space:]]*"[^"]+"[[:space:]]*$' \
    '^description[[:space:]]*=[[:space:]]*"""' \
    '^developer_instructions[[:space:]]*=[[:space:]]*"""' \
    '^model[[:space:]]*=[[:space:]]*"gpt-5\.6-sol"[[:space:]]*$' \
    '^model_reasoning_effort[[:space:]]*=[[:space:]]*"high"[[:space:]]*$' \
    '^sandbox_mode[[:space:]]*=[[:space:]]*"read-only"[[:space:]]*$'

if ((failures > 0)); then
    printf 'Task-Aware Agent validation failed with %d error(s).\n' "$failures" >&2
    exit 1
fi

if [[ "$skip_runtime" == false ]]; then
    if command -v codex >/dev/null 2>&1; then
        if [[ "$config_only_runtime" == true ]]; then
            set +e
            doctor_output=$(CODEX_HOME="$codex_home" codex --strict-config doctor --json --no-color 2>&1)
            doctor_exit=$?
            set -e
            config_status=$(printf '%s\n' "$doctor_output" | awk '
                /"config.load"[[:space:]]*:/ { in_config = 1 }
                in_config && /"status"[[:space:]]*:/ {
                    status = $0
                    sub(/^.*"status"[[:space:]]*:[[:space:]]*"/, "", status)
                    sub(/".*$/, "", status)
                    print status
                    exit
                }
            ')
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
