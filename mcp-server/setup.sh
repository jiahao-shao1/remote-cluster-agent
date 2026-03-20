#!/bin/bash
# Remote Cluster MCP server setup
#
# Single MCP server managing all cluster nodes via the `node` parameter.
#
# Usage:
#   bash setup.sh <nodes_json> <remote_project_dir> [agent_path]
#
# Examples:
#   bash setup.sh '{"train":"ssh -p 2222 gpu-node","eval":"ssh gpu-eval"}' /home/user/project
#   bash setup.sh '{"train":"ssh -p 2222 gpu-node"}' /data/project ~/.mcp-agent/agent.py
#
# Legacy single-node mode (backward compatible):
#   bash setup.sh <name> "<ssh_cmd>" <remote_project_dir>
#   bash setup.sh train "ssh -p 2222 gpu-node" /home/user/project
#
# Prerequisites:
#   1. uv (https://docs.astral.sh/uv/) or pip
#   2. SSH access to cluster established
#   3. Claude Code installed
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Detect mode: multi-node (JSON) or legacy single-node
if echo "$1" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
    # Multi-node mode
    NODES_JSON="$1"
    REMOTE_DIR="${2:-}"
    AGENT_PATH="${3:-~/.mcp-agent/agent.py}"

    if [ -z "$NODES_JSON" ] || [ -z "$REMOTE_DIR" ]; then
        echo "Usage: bash setup.sh <nodes_json> <remote_project_dir> [agent_path]"
        echo ""
        echo "  nodes_json:         JSON dict of {name: ssh_cmd}"
        echo "  remote_project_dir: Project path on cluster"
        echo "  agent_path:         Agent script path on shared storage (default: ~/.mcp-agent/agent.py)"
        echo ""
        echo "Example:"
        echo "  bash setup.sh '{\"train\":\"ssh -p 2222 gpu-node\"}' /home/user/project"
        exit 1
    fi
else
    # Legacy single-node mode
    NAME="${1:-}"
    SSH_CMD="${2:-}"
    REMOTE_DIR="${3:-}"
    AGENT_PATH="${4:-~/.mcp-agent/agent.py}"

    if [ -z "$NAME" ] || [ -z "$SSH_CMD" ] || [ -z "$REMOTE_DIR" ]; then
        echo "Usage: bash setup.sh <name> <ssh_cmd> <remote_project_dir> [agent_path]"
        echo ""
        echo "  name:               Node name (e.g., train, eval)"
        echo "  ssh_cmd:            SSH command (e.g., \"ssh -p 2222 gpu-node\")"
        echo "  remote_project_dir: Project path on cluster"
        echo ""
        echo "Or multi-node mode:"
        echo "  bash setup.sh '{\"train\":\"ssh -p 2222 ...\"}' /project/path"
        exit 1
    fi

    NODES_JSON="{\"$NAME\":\"$SSH_CMD\"}"
    echo "Legacy mode: converting to multi-node format: $NODES_JSON"
fi

# ---- 1. Create venv + install dependencies ----
echo "==> Setting up venv..."
cd "$SCRIPT_DIR"
if [ ! -d ".venv" ]; then
    uv venv --quiet 2>/dev/null || python3 -m venv .venv
    uv pip install --quiet -e . 2>/dev/null || .venv/bin/pip install -q -e .
fi
PYTHON_PATH="$SCRIPT_DIR/.venv/bin/python"
echo "    Python: $PYTHON_PATH"

# ---- 2. Remove old per-node MCP servers ----
echo "==> Cleaning up old MCP servers..."
for old_name in $(claude mcp list 2>/dev/null | grep -oE 'cluster-\w+:' | tr -d ':'); do
    echo "    Removing: $old_name"
    claude mcp remove "$old_name" -s local 2>/dev/null || true
done
# Also remove unified "cluster" if re-running setup
claude mcp remove "cluster" -s local 2>/dev/null || true

# ---- 3. Register unified MCP server ----
echo "==> Registering MCP server: cluster"
claude mcp add "cluster" \
    -e NODES="$NODES_JSON" \
    -e REMOTE_PROJECT_DIR="$REMOTE_DIR" \
    -e REMOTE_AGENT_PATH="$AGENT_PATH" \
    -- "$PYTHON_PATH" "$SCRIPT_DIR/mcp_remote_server.py"

echo ""
echo "=== Setup complete ==="
echo "MCP server:  cluster"
echo "Nodes:       $NODES_JSON"
echo "Remote dir:  $REMOTE_DIR"
echo "Agent path:  $AGENT_PATH"
echo ""
echo "Usage: mcp__cluster__remote_bash(node=\"<name>\", command=\"...\")"
echo ""
echo "Next steps:"
echo "  1. Deploy agent to shared storage (only needed once):"
echo "     scp cluster-agent/agent.py <host>:$AGENT_PATH"
echo "  2. Restart Claude Code to load the new MCP server"
