#!/usr/bin/env bash

set -Eeuo pipefail

usage() {
    cat <<'EOF'
Usage: install-task-aware-agent.sh [OPTIONS]

Install the Codex Task-Aware Agent configuration globally.

Options:
  --codex-home PATH       Target Codex home (default: $CODEX_HOME or ~/.codex)
  --set-sol-default       Set gpt-5.6-sol with xhigh reasoning as the default
  --enable-full-access    Set approval_policy=never and danger-full-access
  -h, --help              Show this help
EOF
}

die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

codex_home="${CODEX_HOME:-$HOME/.codex}"
set_sol_default=false
enable_full_access=false

while (($# > 0)); do
    case "$1" in
        --codex-home)
            (($# >= 2)) || die '--codex-home requires a path'
            codex_home=$2
            shift 2
            ;;
        --set-sol-default)
            set_sol_default=true
            shift
            ;;
        --enable-full-access)
            enable_full_access=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "unknown option: $1"
            ;;
    esac
done

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repository_root=$(cd -- "$script_dir/.." && pwd -P)
agents_source="$repository_root/agents"
policy_source="$repository_root/config/AGENTS.task-aware.md"
config_path="$codex_home/config.toml"
agents_path="$codex_home/agents"
agents_md_path="$codex_home/AGENTS.md"
timestamp=$(date '+%Y%m%d-%H%M%S')
backup_path="$codex_home/task-aware-backups/$timestamp"
backup_suffix=0

while [[ -e "$backup_path" ]]; do
    backup_suffix=$((backup_suffix + 1))
    backup_path="$codex_home/task-aware-backups/$timestamp-$backup_suffix"
done

[[ -d "$agents_source" ]] || die "missing agents directory: $agents_source"
[[ -f "$policy_source" ]] || die "missing policy file: $policy_source"
command -v awk >/dev/null || die 'awk is required'

expected_agent_files=(
    luna-task.toml
    luna-task-max.toml
    terra-worker.toml
    terra-worker-max.toml
    sol-specialist.toml
    sol-specialist-max.toml
)
retired_agent_files=(luna-task-high.toml terra-worker-high.toml)
for agent_file in "${expected_agent_files[@]}"; do
    [[ -f "$agents_source/$agent_file" ]] || die "missing agent file: $agents_source/$agent_file"
done

validate_policy_markers() {
    local path=$1

    awk '
        BEGIN {
            begin_marker = "<!-- BEGIN CODEX TASK-AWARE AGENT -->"
            end_marker = "<!-- END CODEX TASK-AWARE AGENT -->"
        }

        $0 == begin_marker {
            begin_count++
            if (begin_count > 1 || end_count > 0) invalid = 1
        }

        $0 == end_marker {
            end_count++
            if (begin_count != 1 || end_count > 1) invalid = 1
        }

        END {
            if (invalid || begin_count != end_count || begin_count > 1) exit 1
        }
    ' "$path"
}

backup_if_present() {
    local source=$1
    local relative destination

    [[ -f "$source" ]] || return 0
    relative=${source#"$codex_home"/}
    destination="$backup_path/$relative"
    mkdir -p -- "$(dirname -- "$destination")"
    cp -p -- "$source" "$destination"
}

replace_file() {
    local temporary=$1
    local destination=$2

    cat -- "$temporary" > "$destination"
    rm -f -- "$temporary"
}

set_toml_section_value() {
    local path=$1
    local section=$2
    local key=$3
    local value=$4
    local temporary

    temporary=$(mktemp "$codex_home/.task-aware-config.XXXXXX")
    awk -v section="$section" -v key="$key" -v value="$value" '
        function emit_value() {
            if (!key_written) {
                print key " = " value
                key_written = 1
            }
        }

        $0 ~ "^[[:space:]]*\\[" section "\\][[:space:]]*(#.*)?$" {
            section_found = 1
            in_section = 1
            print
            next
        }

        in_section && $0 ~ "^[[:space:]]*\\[[^]]+\\][[:space:]]*(#.*)?$" {
            emit_value()
            in_section = 0
        }

        in_section && $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
            if (!key_written) {
                print key " = " value
                key_written = 1
            }
            next
        }

        { print }

        END {
            if (in_section) {
                emit_value()
            } else if (!section_found) {
                if (NR > 0) print ""
                print "[" section "]"
                print key " = " value
            }
        }
    ' "$path" > "$temporary"
    replace_file "$temporary" "$path"
}

set_top_level_toml_value() {
    local path=$1
    local key=$2
    local value=$3
    local temporary

    temporary=$(mktemp "$codex_home/.task-aware-config.XXXXXX")
    awk -v key="$key" -v value="$value" '
        BEGIN { before_section = 1 }

        before_section && $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
            if (!key_written) {
                print key " = " value
                key_written = 1
            }
            next
        }

        before_section && $0 ~ "^[[:space:]]*\\[[^]]+\\][[:space:]]*(#.*)?$" {
            if (!key_written) {
                print key " = " value
                print ""
                key_written = 1
            }
            before_section = 0
        }

        { print }

        END {
            if (!key_written) {
                if (NR > 0) print ""
                print key " = " value
            }
        }
    ' "$path" > "$temporary"
    replace_file "$temporary" "$path"
}

remove_toml_section_key() {
    local path=$1
    local section=$2
    local key=$3
    local temporary

    temporary=$(mktemp "$codex_home/.task-aware-config.XXXXXX")
    awk -v section="$section" -v key="$key" '
        $0 ~ "^[[:space:]]*\\[" section "\\][[:space:]]*(#.*)?$" {
            in_section = 1
            print
            next
        }

        in_section && $0 ~ "^[[:space:]]*\\[[^]]+\\][[:space:]]*(#.*)?$" {
            in_section = 0
        }

        in_section && $0 ~ "^[[:space:]]*" key "[[:space:]]*=" { next }
        { print }
    ' "$path" > "$temporary"
    replace_file "$temporary" "$path"
}

merge_policy_block() {
    local destination=$1
    local temporary

    temporary=$(mktemp "$codex_home/.task-aware-agents.XXXXXX")
    awk -v policy_file="$policy_source" '
        BEGIN {
            begin_marker = "<!-- BEGIN CODEX TASK-AWARE AGENT -->"
            end_marker = "<!-- END CODEX TASK-AWARE AGENT -->"
            while ((getline policy_line < policy_file) > 0) {
                policy[++policy_count] = policy_line
            }
            close(policy_file)
        }

        function emit_policy(    i) {
            for (i = 1; i <= policy_count; i++) print policy[i]
        }

        $0 == begin_marker {
            if (!policy_written) {
                emit_policy()
                policy_written = 1
            }
            block_found = 1
            skipping = 1
            next
        }

        skipping {
            if ($0 == end_marker) skipping = 0
            next
        }

        { print }

        END {
            if (!block_found) {
                if (NR > 0) print ""
                emit_policy()
            }
        }
    ' "$destination" > "$temporary"
    replace_file "$temporary" "$destination"
}

if [[ -f "$agents_md_path" ]] && ! validate_policy_markers "$agents_md_path"; then
    die 'AGENTS.md contains malformed or duplicate Task-Aware Agent markers; repair the marker block before retrying'
fi

if [[ "$enable_full_access" == true && -f "$config_path" ]] &&
    grep -Eq '^[[:space:]]*default_permissions[[:space:]]*=' "$config_path"; then
    die 'cannot use --enable-full-access while config.toml defines default_permissions; remove one permission system before retrying'
fi

mkdir -p -- "$codex_home" "$agents_path" "$backup_path"

backup_if_present "$config_path"
backup_if_present "$agents_md_path"
for agent_file in "${expected_agent_files[@]}"; do
    backup_if_present "$agents_path/$agent_file"
done
for agent_file in "${retired_agent_files[@]}"; do
    backup_if_present "$agents_path/$agent_file"
done

touch -- "$config_path" "$agents_md_path"

set_toml_section_value "$config_path" agents enabled true
set_toml_section_value "$config_path" agents max_concurrent_threads_per_session 3
remove_toml_section_key "$config_path" agents max_threads
remove_toml_section_key "$config_path" agents max_depth
remove_toml_section_key "$config_path" features multi_agent

if [[ "$set_sol_default" == true ]]; then
    set_top_level_toml_value "$config_path" model '"gpt-5.6-sol"'
    set_top_level_toml_value "$config_path" model_reasoning_effort '"xhigh"'
fi

if [[ "$enable_full_access" == true ]]; then
    set_top_level_toml_value "$config_path" approval_policy '"never"'
    set_top_level_toml_value "$config_path" sandbox_mode '"danger-full-access"'
fi

merge_policy_block "$agents_md_path"
for agent_file in "${expected_agent_files[@]}"; do
    cp -f -- "$agents_source/$agent_file" "$agents_path/$agent_file"
done
for agent_file in "${retired_agent_files[@]}"; do
    rm -f -- "$agents_path/$agent_file"
done

printf 'Installed Task-Aware Agent configuration in %s\n' "$codex_home"
printf 'Backup: %s\n' "$backup_path"
printf '%s\n' 'Restart Codex or start a new task to load the updated instruction chain.'
