#!/usr/bin/env bash

set -Eeuo pipefail

usage() {
    cat <<'EOF'
Usage: test-task-aware-agent.sh [OPTIONS]

Validate an installed Codex Task-Aware Agent configuration.

Options:
  --codex-home PATH  Target Codex home (default: $CODEX_HOME or ~/.codex)
  --skip-runtime     Skip the codex doctor runtime check
  -h, --help         Show this help
EOF
}

codex_home="${CODEX_HOME:-$HOME/.codex}"
skip_runtime=false

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
    '^\[features\][[:space:]]*$' \
    '^multi_agent[[:space:]]*=[[:space:]]*true[[:space:]]*$' \
    '^\[agents\][[:space:]]*$' \
    '^max_threads[[:space:]]*=[[:space:]]*4[[:space:]]*$' \
    '^max_depth[[:space:]]*=[[:space:]]*1[[:space:]]*$'

assert_file_contains "$agents_md_path" \
    '<!-- BEGIN CODEX TASK-AWARE AGENT -->' \
    'Task-aware delegation policy' \
    '<!-- END CODEX TASK-AWARE AGENT -->'

assert_file_contains "$agents_path/luna-task.toml" \
    '^name[[:space:]]*=[[:space:]]*"[^"]+"[[:space:]]*$' \
    '^description[[:space:]]*=[[:space:]]*"""' \
    '^developer_instructions[[:space:]]*=[[:space:]]*"""' \
    '^model[[:space:]]*=[[:space:]]*"gpt-5\.6-luna"[[:space:]]*$'

assert_file_contains "$agents_path/terra-worker.toml" \
    '^name[[:space:]]*=[[:space:]]*"[^"]+"[[:space:]]*$' \
    '^description[[:space:]]*=[[:space:]]*"""' \
    '^developer_instructions[[:space:]]*=[[:space:]]*"""' \
    '^model[[:space:]]*=[[:space:]]*"gpt-5\.6-terra"[[:space:]]*$'

assert_file_contains "$agents_path/sol-specialist.toml" \
    '^name[[:space:]]*=[[:space:]]*"[^"]+"[[:space:]]*$' \
    '^description[[:space:]]*=[[:space:]]*"""' \
    '^developer_instructions[[:space:]]*=[[:space:]]*"""' \
    '^model[[:space:]]*=[[:space:]]*"gpt-5\.6-sol"[[:space:]]*$'

if ((failures > 0)); then
    printf 'Task-Aware Agent validation failed with %d error(s).\n' "$failures" >&2
    exit 1
fi

if [[ "$skip_runtime" == false ]]; then
    if command -v codex >/dev/null 2>&1; then
        CODEX_HOME="$codex_home" codex --strict-config doctor --summary --no-color --ascii
    else
        printf '%s\n' 'Warning: codex was not found; file validation passed but runtime validation was skipped.' >&2
    fi
fi

printf '%s\n' 'Task-Aware Agent validation passed.'
