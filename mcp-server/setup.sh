#!/bin/bash
# Remote Cluster MCP + Mutagen link manager
#
# Commands:
#   add     Register MCP + create Mutagen session
#   list    List links managed by this script
#   remove  Remove MCP + terminate Mutagen session
#
# Examples:
#   bash setup.sh add train "$PWD" "ssh -p 2222 gpu-node" /home/user/project
#   bash setup.sh list
#   bash setup.sh remove train
#
# Prerequisites:
#   1. uv installed (https://docs.astral.sh/uv/)
#   2. mutagen installed (https://mutagen.io/documentation/introduction/getting-started)
#   3. SSH access to cluster established
#   4. Claude Code or Codex CLI installed
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REGISTRY_DIR="${HOME}/.remote-cluster-agent"
REGISTRY_FILE="${REGISTRY_DIR}/links.tsv"

COMMAND="add"
LOCAL_DIR=""
CLIENT=""
MUTAGEN_ENDPOINT=""
MUTAGEN_MODE="two-way-safe"
NAME=""
SSH_CMD=""
REMOTE_DIR=""
MUTAGEN_IGNORE_ARGS=()

usage() {
    echo "Usage:"
    echo "  bash setup.sh add [--client claude|codex] [--mutagen-endpoint <endpoint>] [--mutagen-mode <mode>] <name> <local_project_dir> <ssh_cmd> <remote_project_dir>"
    echo "  bash setup.sh list [--client claude|codex]"
    echo "  bash setup.sh remove [--client claude|codex] <name>"
    echo ""
    echo "Commands:"
    echo "  add:                Create or replace a managed link."
    echo "  list:               Show managed links recorded by this script."
    echo "  remove:             Remove a managed link (MCP config + Mutagen session)."
    echo ""
    echo "Options:"
    echo "  --client:           Optional. Force the target client."
    echo "                      If omitted, the script auto-detects Claude/Codex."
    echo "  --mutagen-endpoint: Optional. Override the remote Mutagen SSH endpoint."
    echo "                      Format: [user@]host[:port]:/absolute/path"
    echo "  --mutagen-mode:     Optional. Mutagen sync mode for 'add'."
    echo "                      Default: two-way-safe"
    echo ""
    echo "Examples:"
    echo "  bash setup.sh add train \"\$PWD\" \"ssh -p 2222 gpu-node\" /home/user/project"
    echo "  bash setup.sh add --client claude train \"\$PWD\" \"ssh -p 2222 gpu-node\" /home/user/project"
    echo "  bash setup.sh list"
    echo "  bash setup.sh remove train"
}

mcp_server_name() {
    printf "cluster-%s\n" "$1"
}

mutagen_session_name() {
    printf "cluster-%s-files\n" "$1"
}

ensure_registry() {
    mkdir -p "$REGISTRY_DIR"
    touch "$REGISTRY_FILE"
}

registry_lookup() {
    local name="$1"
    [ -f "$REGISTRY_FILE" ] || return 1
    awk -F '\t' -v name="$name" '$1 == name { print; exit }' "$REGISTRY_FILE"
}

registry_upsert() {
    local name="$1"
    local client="$2"
    local local_dir="$3"
    local ssh_cmd="$4"
    local remote_dir="$5"
    local endpoint="$6"
    local mode="$7"
    local tmp

    ensure_registry
    tmp="$(mktemp)"
    awk -F '\t' -v name="$name" '$1 != name { print }' "$REGISTRY_FILE" > "$tmp" 2>/dev/null || true
    printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
        "$name" "$client" "$local_dir" "$ssh_cmd" "$remote_dir" "$endpoint" "$mode" >> "$tmp"
    mv "$tmp" "$REGISTRY_FILE"
}

registry_remove() {
    local name="$1"
    local tmp

    [ -f "$REGISTRY_FILE" ] || return 0
    tmp="$(mktemp)"
    awk -F '\t' -v name="$name" '$1 != name { print }' "$REGISTRY_FILE" > "$tmp" 2>/dev/null || true
    mv "$tmp" "$REGISTRY_FILE"
}

detect_client() {
    local has_claude=0
    local has_codex=0

    if command -v claude >/dev/null 2>&1; then
        has_claude=1
    fi
    if command -v codex >/dev/null 2>&1; then
        has_codex=1
    fi

    if [ "$has_claude" -eq 1 ] && [ "$has_codex" -eq 0 ]; then
        printf "claude\n"
    elif [ "$has_claude" -eq 0 ] && [ "$has_codex" -eq 1 ]; then
        printf "codex\n"
    elif [ "$has_claude" -eq 1 ] && [ "$has_codex" -eq 1 ]; then
        printf "claude\n"
        echo "==> Both Claude Code and Codex were detected; defaulting to Claude Code." >&2
        echo "    Use --client codex to register with Codex instead." >&2
    else
        echo "Error: neither 'claude' nor 'codex' was found in PATH." >&2
        exit 1
    fi
}

derive_mutagen_endpoint() {
    local ssh_cmd="$1"
    local remote_dir="$2"
    local -a parts=()
    local token=""
    local host=""
    local port=""
    local user=""
    local i=1

    read -r -a parts <<< "$ssh_cmd"

    if [ "${#parts[@]}" -lt 2 ] || [ "${parts[0]}" != "ssh" ]; then
        return 1
    fi

    while [ "$i" -lt "${#parts[@]}" ]; do
        token="${parts[$i]}"
        case "$token" in
            -p)
                i=$((i + 1))
                [ "$i" -lt "${#parts[@]}" ] || return 1
                port="${parts[$i]}"
                ;;
            -l)
                i=$((i + 1))
                [ "$i" -lt "${#parts[@]}" ] || return 1
                user="${parts[$i]}"
                ;;
            --)
                i=$((i + 1))
                break
                ;;
            -*)
                return 1
                ;;
            *)
                host="$token"
                i=$((i + 1))
                break
                ;;
        esac
        i=$((i + 1))
    done

    if [ -z "$host" ] || [ "$i" -ne "${#parts[@]}" ]; then
        return 1
    fi

    if [[ "$host" == *"@"* ]]; then
        [ -z "$user" ] || return 1
    elif [ -n "$user" ]; then
        host="${user}@${host}"
    fi

    if [ -n "$port" ]; then
        printf "%s:%s:%s\n" "$host" "$port" "$remote_dir"
    else
        printf "%s:%s\n" "$host" "$remote_dir"
    fi
}

build_mutagen_ignore_args() {
    local local_dir="$1"
    local gitignore_path="$local_dir/.gitignore"
    local line=""

    MUTAGEN_IGNORE_ARGS=()

    if [ ! -f "$gitignore_path" ]; then
        return 0
    fi

    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%$'\r'}"

        if [ -z "$line" ]; then
            continue
        fi

        case "$line" in
            \#*)
                continue
                ;;
        esac

        MUTAGEN_IGNORE_ARGS+=("--ignore" "$line")
    done < "$gitignore_path"
}

register_mcp() {
    local client="$1"
    local name="$2"
    local ssh_cmd="$3"
    local remote_dir="$4"
    local python_path="$5"
    local server_name

    server_name="$(mcp_server_name "$name")"

    echo "==> Registering MCP server: $server_name"
    if [ "$client" = "claude" ]; then
        claude mcp add "$server_name" \
            -e SSH_CMD="$ssh_cmd" \
            -e REMOTE_PROJECT_DIR="$remote_dir" \
            -- "$python_path" "$SCRIPT_DIR/mcp_remote_server.py"
    else
        codex mcp add "$server_name" \
            --env SSH_CMD="$ssh_cmd" \
            --env REMOTE_PROJECT_DIR="$remote_dir" \
            -- "$python_path" "$SCRIPT_DIR/mcp_remote_server.py"
    fi
}

remove_mcp() {
    local client="$1"
    local name="$2"
    local server_name

    server_name="$(mcp_server_name "$name")"
    echo "==> Removing MCP server: $server_name"
    if [ "$client" = "claude" ]; then
        claude mcp remove "$server_name" >/dev/null 2>&1 || true
    else
        codex mcp remove "$server_name" >/dev/null 2>&1 || true
    fi
}

create_mutagen_session() {
    local name="$1"
    local local_dir="$2"
    local endpoint="$3"
    local mode="$4"
    local session_name

    session_name="$(mutagen_session_name "$name")"
    echo "==> Recreating Mutagen sync session: $session_name"
    mutagen sync terminate "$session_name" >/dev/null 2>&1 || true
    mutagen sync create \
        --name "$session_name" \
        --label "remote-cluster-agent=true" \
        --label "cluster-name=$name" \
        --mode "$mode" \
        "${MUTAGEN_IGNORE_ARGS[@]}" \
        "$local_dir" \
        "$endpoint"
}

remove_mutagen_session() {
    local name="$1"
    local session_name

    session_name="$(mutagen_session_name "$name")"
    echo "==> Terminating Mutagen sync session: $session_name"
    mutagen sync terminate "$session_name" >/dev/null 2>&1 || true
}

print_link_summary() {
    local name="$1"
    local client="$2"
    local local_dir="$3"
    local ssh_cmd="$4"
    local remote_dir="$5"
    local endpoint="$6"
    local mode="$7"

    echo ""
    echo "=== Link configured ==="
    echo "Client:      $client"
    echo "MCP server:  $(mcp_server_name "$name")"
    echo "Sync name:   $(mutagen_session_name "$name")"
    echo "SSH command: $ssh_cmd"
    echo "Local dir:   $local_dir"
    echo "Remote dir:  $remote_dir"
    echo "Endpoint:    $endpoint"
    echo "Sync mode:   $mode"
    echo ""
    if [ "$client" = "claude" ]; then
        echo "Use in Claude Code: mcp__cluster-${name}__remote_bash"
    else
        echo "Check in Codex: codex mcp get $(mcp_server_name "$name") --json"
    fi
    echo "Check sync status: mutagen sync list $(mutagen_session_name "$name")"
    echo "Force a sync cycle: mutagen sync flush $(mutagen_session_name "$name")"
    if [ -f "$local_dir/.gitignore" ]; then
        echo "Ignore source: $local_dir/.gitignore"
        echo "If .gitignore changes, rerun 'setup.sh add ...' to recreate the session with updated ignores."
    else
        echo "Ignore source: none (.git and other files will sync unless excluded elsewhere)"
    fi
}

list_links() {
    local filter_client="$1"
    local found=0
    local name=""
    local client=""
    local local_dir=""
    local ssh_cmd=""
    local remote_dir=""
    local endpoint=""
    local mode=""

    if [ ! -f "$REGISTRY_FILE" ] || [ ! -s "$REGISTRY_FILE" ]; then
        echo "No managed links found."
        return 0
    fi

    printf "%-18s %-8s %-24s %-24s %-22s\n" "NAME" "CLIENT" "LOCAL" "REMOTE" "SYNC"
    while IFS=$'\t' read -r name client local_dir ssh_cmd remote_dir endpoint mode; do
        [ -n "$name" ] || continue
        if [ -n "$filter_client" ] && [ "$client" != "$filter_client" ]; then
            continue
        fi
        found=1
        printf "%-18s %-8s %-24s %-24s %-22s\n" \
            "$name" "$client" "$local_dir" "$remote_dir" "$(mutagen_session_name "$name")"
    done < "$REGISTRY_FILE"

    if [ "$found" -eq 0 ]; then
        echo "No managed links found."
    else
        echo ""
        echo "These entries are the links managed by this script."
        echo "Use 'bash setup.sh remove <name>' to remove a link."
    fi
}

if [ "${1:-}" = "add" ] || [ "${1:-}" = "list" ] || [ "${1:-}" = "remove" ] || [ "${1:-}" = "help" ]; then
    COMMAND="${1:-}"
    shift
fi

while [ "$#" -gt 0 ]; do
    case "${1:-}" in
        --client)
            CLIENT="${2:-}"
            shift 2
            ;;
        --local-dir)
            echo "Error: --local-dir has been removed. Pass <local_project_dir> as the second positional argument to 'add'."
            exit 1
            ;;
        --mutagen-endpoint)
            MUTAGEN_ENDPOINT="${2:-}"
            shift 2
            ;;
        --mutagen-mode)
            MUTAGEN_MODE="${2:-}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            break
            ;;
        -*)
            echo "Error: unknown option '$1'"
            echo ""
            usage
            exit 1
            ;;
        *)
            break
            ;;
    esac
done

if [ "$COMMAND" = "help" ]; then
    usage
    exit 0
fi

if [ -n "$CLIENT" ] && [ "$CLIENT" != "claude" ] && [ "$CLIENT" != "codex" ]; then
    echo "Error: --client must be 'claude' or 'codex'"
    echo ""
    usage
    exit 1
fi

case "$COMMAND" in
    add)
        NAME="${1:-}"
        LOCAL_DIR="${2:-}"
        SSH_CMD="${3:-}"
        REMOTE_DIR="${4:-}"
        ;;
    remove)
        NAME="${1:-}"
        ;;
    list)
        ;;
    *)
        usage
        exit 1
        ;;
esac

if [ "$COMMAND" = "list" ]; then
    list_links "$CLIENT"
    exit 0
fi

if [ -z "$NAME" ]; then
    usage
    exit 1
fi

if [ -z "$CLIENT" ]; then
    CLIENT="$(detect_client)"
fi

if [ "$COMMAND" = "remove" ]; then
    if registry_lookup "$NAME" >/dev/null 2>&1; then
        IFS=$'\t' read -r _ registry_client _ _ _ _ _ <<< "$(registry_lookup "$NAME")"
        CLIENT="${registry_client:-$CLIENT}"
    fi

    remove_mcp "$CLIENT" "$NAME"
    remove_mutagen_session "$NAME"
    registry_remove "$NAME"
    echo "Removed link: $NAME"
    exit 0
fi

if [ -z "$LOCAL_DIR" ] || [ -z "$SSH_CMD" ] || [ -z "$REMOTE_DIR" ]; then
    usage
    exit 1
fi

if [ "$MUTAGEN_MODE" != "two-way-safe" ] && [ "$MUTAGEN_MODE" != "two-way-resolved" ] && [ "$MUTAGEN_MODE" != "one-way-safe" ] && [ "$MUTAGEN_MODE" != "one-way-replica" ]; then
    echo "Error: --mutagen-mode must be one of: two-way-safe, two-way-resolved, one-way-safe, one-way-replica"
    exit 1
fi

if [ ! -d "$LOCAL_DIR" ]; then
    echo "Error: local directory does not exist: $LOCAL_DIR"
    exit 1
fi

LOCAL_DIR="$(cd "$LOCAL_DIR" && pwd)"

if [ ! -d "$LOCAL_DIR/.git" ] && [ ! -f "$LOCAL_DIR/.gitignore" ]; then
    echo "Warning: $LOCAL_DIR doesn't look like a Git working tree."
    echo "         Mutagen will still work, but .gitignore-derived ignores may be incomplete."
fi

if ! command -v uv >/dev/null 2>&1; then
    echo "Error: uv is required but was not found in PATH."
    exit 1
fi

if ! command -v mutagen >/dev/null 2>&1; then
    echo "Error: mutagen is required but was not found in PATH."
    exit 1
fi

if [ -z "$MUTAGEN_ENDPOINT" ]; then
    if ! MUTAGEN_ENDPOINT="$(derive_mutagen_endpoint "$SSH_CMD" "$REMOTE_DIR")"; then
        echo "Error: couldn't derive a Mutagen SSH endpoint from: $SSH_CMD"
        echo "       Use --mutagen-endpoint [user@]host[:port]:$REMOTE_DIR or switch to an SSH alias."
        echo "       Mutagen uses OpenSSH host/port syntax, so complex SSH options should live in ~/.ssh/config."
        exit 1
    fi
fi

build_mutagen_ignore_args "$LOCAL_DIR"

echo "==> Creating venv..."
cd "$SCRIPT_DIR"
if [ ! -d ".venv" ]; then
    uv venv --quiet
    uv pip install --quiet -e .
fi
PYTHON_PATH="$SCRIPT_DIR/.venv/bin/python"
echo "    Python: $PYTHON_PATH"

register_mcp "$CLIENT" "$NAME" "$SSH_CMD" "$REMOTE_DIR" "$PYTHON_PATH"
create_mutagen_session "$NAME" "$LOCAL_DIR" "$MUTAGEN_ENDPOINT" "$MUTAGEN_MODE"
registry_upsert "$NAME" "$CLIENT" "$LOCAL_DIR" "$SSH_CMD" "$REMOTE_DIR" "$MUTAGEN_ENDPOINT" "$MUTAGEN_MODE"
print_link_summary "$NAME" "$CLIENT" "$LOCAL_DIR" "$SSH_CMD" "$REMOTE_DIR" "$MUTAGEN_ENDPOINT" "$MUTAGEN_MODE"
