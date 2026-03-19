#!/bin/bash
# Remote Cluster MCP server installer
#
# Usage:
#   bash setup.sh [--client claude|codex] <name> <ssh_cmd> <remote_project_dir>
#
# Examples:
#   bash setup.sh train "ssh -p 2222 gpu-node" /home/user/project
#   bash setup.sh --client codex eval "ssh gpu-eval" /data/project
#
# Prerequisites:
#   1. uv installed (https://docs.astral.sh/uv/)
#   2. SSH access to cluster established
#   3. Claude Code or Codex CLI installed
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

usage() {
    echo "Usage: bash setup.sh [--client claude|codex] <name> <ssh_cmd> <remote_project_dir>"
    echo ""
    echo "  --client:           Optional. Force the target client."
    echo "                      If omitted, the script auto-detects Claude/Codex."
    echo "  name:               MCP server name (e.g., train, eval)"
    echo "  ssh_cmd:            SSH command (e.g., \"ssh -p 2222 gpu-node\")"
    echo "  remote_project_dir: Project path on cluster (e.g., /home/user/project)"
    echo ""
    echo "Examples:"
    echo "  bash setup.sh train \"ssh -p 2222 gpu-node\" /home/user/project"
    echo "  bash setup.sh --client claude train \"ssh -p 2222 gpu-node\" /home/user/project"
    echo "  bash setup.sh --client codex eval \"ssh gpu-eval\" /data/project"
}

CLIENT=""

if [ "${1:-}" = "--client" ]; then
    CLIENT="${2:-}"
    shift 2
fi

NAME="${1:-}"
SSH_CMD="${2:-}"
REMOTE_DIR="${3:-}"

if [ -z "$NAME" ] || [ -z "$SSH_CMD" ] || [ -z "$REMOTE_DIR" ]; then
    usage
    exit 1
fi

if [ -n "$CLIENT" ] && [ "$CLIENT" != "claude" ] && [ "$CLIENT" != "codex" ]; then
    echo "Error: --client must be 'claude' or 'codex'"
    echo ""
    usage
    exit 1
fi

if [ -z "$CLIENT" ]; then
    HAS_CLAUDE=0
    HAS_CODEX=0

    if command -v claude >/dev/null 2>&1; then
        HAS_CLAUDE=1
    fi
    if command -v codex >/dev/null 2>&1; then
        HAS_CODEX=1
    fi

    if [ "$HAS_CLAUDE" -eq 1 ] && [ "$HAS_CODEX" -eq 0 ]; then
        CLIENT="claude"
    elif [ "$HAS_CLAUDE" -eq 0 ] && [ "$HAS_CODEX" -eq 1 ]; then
        CLIENT="codex"
    elif [ "$HAS_CLAUDE" -eq 1 ] && [ "$HAS_CODEX" -eq 1 ]; then
        CLIENT="claude"
        echo "==> Both Claude Code and Codex were detected; defaulting to Claude Code."
        echo "    Use --client codex to register with Codex instead."
    else
        echo "Error: neither 'claude' nor 'codex' was found in PATH."
        exit 1
    fi
fi

# ---- 1. Create venv + install dependencies ----
echo "==> Creating venv..."
cd "$SCRIPT_DIR"
if [ ! -d ".venv" ]; then
    uv venv --quiet
    uv pip install --quiet -e .
fi
PYTHON_PATH="$SCRIPT_DIR/.venv/bin/python"
echo "    Python: $PYTHON_PATH"

# ---- 2. Register MCP server ----
echo "==> Registering MCP server: cluster-$NAME"
if [ "$CLIENT" = "claude" ]; then
    claude mcp add "cluster-$NAME" \
        -e SSH_CMD="$SSH_CMD" \
        -e REMOTE_PROJECT_DIR="$REMOTE_DIR" \
        -- "$PYTHON_PATH" "$SCRIPT_DIR/mcp_remote_server.py"
else
    codex mcp add "cluster-$NAME" \
        --env SSH_CMD="$SSH_CMD" \
        --env REMOTE_PROJECT_DIR="$REMOTE_DIR" \
        -- "$PYTHON_PATH" "$SCRIPT_DIR/mcp_remote_server.py"
fi

echo ""
echo "=== Installation complete ==="
echo "Client:      $CLIENT"
echo "MCP server:  cluster-$NAME"
echo "SSH command: $SSH_CMD"
echo "Remote dir:  $REMOTE_DIR"
echo ""
if [ "$CLIENT" = "claude" ]; then
    echo "Use in Claude Code: mcp__cluster-${NAME}__remote_bash"
else
    echo "Check in Codex: codex mcp get cluster-$NAME --json"
fi
