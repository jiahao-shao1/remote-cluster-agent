#!/bin/bash
# Remote Cluster MCP server installer
#
# Usage:
#   bash setup.sh <name> <ssh_cmd> [remote_project_dir]
#
# Examples:
#   bash setup.sh train "ssh -p 2222 gpu-node" /home/user/project
#   bash setup.sh eval  "ssh gpu-eval" /data/project
#
# Prerequisites:
#   1. uv installed (https://docs.astral.sh/uv/)
#   2. SSH access to cluster established
#   3. Claude Code installed
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

NAME="${1:-}"
SSH_CMD="${2:-}"
REMOTE_DIR="${3:-}"

if [ -z "$NAME" ] || [ -z "$SSH_CMD" ] || [ -z "$REMOTE_DIR" ]; then
    echo "Usage: bash setup.sh <name> <ssh_cmd> <remote_project_dir>"
    echo ""
    echo "  name:               MCP server name (e.g., train, eval)"
    echo "  ssh_cmd:            SSH command (e.g., \"ssh -p 2222 gpu-node\")"
    echo "  remote_project_dir: Project path on cluster (e.g., /home/user/project)"
    echo ""
    echo "Examples:"
    echo "  bash setup.sh train \"ssh -p 2222 gpu-node\" /home/user/project"
    echo "  bash setup.sh eval  \"ssh gpu-eval\" /data/project"
    exit 1
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

# ---- 2. Register with Claude Code ----
echo "==> Registering MCP server: cluster-$NAME"
claude mcp add "cluster-$NAME" \
    -e SSH_CMD="$SSH_CMD" \
    -e REMOTE_PROJECT_DIR="$REMOTE_DIR" \
    -- "$PYTHON_PATH" "$SCRIPT_DIR/mcp_remote_server.py"

echo ""
echo "=== Installation complete ==="
echo "MCP server:  cluster-$NAME"
echo "SSH command:  $SSH_CMD"
echo "Remote dir:   $REMOTE_DIR"
echo ""
echo "Use in Claude Code: mcp__cluster-${NAME}__remote_bash"
