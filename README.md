# Remote Cluster Agent

![Version](https://img.shields.io/badge/version-0.1.0-blue)

English | [中文](README.zh-CN.md)

> Enable coding agents to iterate on air-gapped GPU clusters. Edit locally, execute remotely, sync your way.

## Why This Exists

Many GPU clusters (private cloud, on-prem HPC, air-gapped environments) have no public internet. Running a full coding agent remotely is either impossible or painfully slow — remote file operations via MCP proxy are ~2000x slower than local ones.

This skill flips the model: **keep all read/write local, only send bash commands to the cluster**.

### Architecture

```
Local Machine (has internet)              GPU Cluster (no internet)
├── Coding Agent (Claude Code / Codex)    └── /path/to/project/
├── Native tools (Read/Edit/Write)            ├── training scripts
│   ~0.5ms per operation                      ├── checkpoints
├── code sync (git/rsync/your way) ────────> pull changes
├── remote_bash MCP ───sentinel+kill───────> bash commands
└── log sync (your way) <──────────────────── training outputs
```

### The Automation Loop

```
Edit code (local) → Sync code → Run experiment (remote) → Sync logs → Read results (local) → repeat
```

- **Code editing**: Local native tools (fast, ~0.5ms)
- **Code sync**: Any method your team already uses (git push/pull, rsync, shared filesystem, etc.)
- **Remote execution**: `remote_bash` MCP tool (sentinel pattern handles non-closing SSH proxies)
- **Log sync**: Any method your team already uses (object storage, rsync, shared filesystem, etc.)
- **Reading results**: Local native Read tool (~20x faster than reading through remote MCP)

## Quick Start

### 1. Install the skill

For Claude Code:

```bash
npx skills add https://github.com/jiahao-shao1/remote-cluster-agent
```

For Codex:

```bash
mkdir -p ~/.codex/skills
ln -s /path/to/remote-cluster-agent ~/.codex/skills/remote-cluster-agent
```

### 2. Install the MCP server

The installer now supports both Claude Code and Codex. It auto-detects the client by default; if both are installed, use `--client` to pick one explicitly.

For Claude Code:

```bash
bash .agents/skills/remote-cluster-agent/mcp-server/setup.sh --client claude <name> "<ssh_cmd>" <remote_project_dir>

# Example: register two nodes
bash .agents/skills/remote-cluster-agent/mcp-server/setup.sh --client claude train "ssh -p 2222 gpu-node" /home/user/project
bash .agents/skills/remote-cluster-agent/mcp-server/setup.sh --client claude eval  "ssh gpu-eval" /data/project
```

For Codex:

```bash
bash .agents/skills/remote-cluster-agent/mcp-server/setup.sh --client codex <name> "<ssh_cmd>" <remote_project_dir>

# Example: register two nodes
bash .agents/skills/remote-cluster-agent/mcp-server/setup.sh --client codex train "ssh -p 2222 gpu-node" /home/user/project
bash .agents/skills/remote-cluster-agent/mcp-server/setup.sh --client codex eval  "ssh gpu-eval" /data/project
```

Auto-detect example:

```bash
bash .agents/skills/remote-cluster-agent/mcp-server/setup.sh train "ssh -p 2222 gpu-node" /home/user/project
```

Prerequisites: [uv](https://docs.astral.sh/uv/), SSH access to cluster, Claude Code or Codex CLI installed.

### 3. Restart your client

After installing, restart the client you use so it reloads the new MCP server:

- Claude Code: restart Claude Code
- Codex: restart the Codex CLI session

Then just describe what you want to do on the cluster.

### 4. First-time interactive setup

On first use, your agent will ask you a few questions (SSH endpoints, paths, sync methods, safety rules) and generate your personal `reference/context.local.md`. This file is gitignored — your config stays private.

## File Structure

```
remote-cluster-agent/
├── SKILL.md                          # Skill instructions (generic, no personal info)
├── README.md                         # This file
├── README.zh-CN.md                   # Chinese version
├── .gitignore                        # Excludes context.local.md and .venv
├── .claude/
│   └── agents/
│       └── cluster-operator.md       # Subagent for cluster ops (auto-dispatched)
├── mcp-server/
│   ├── mcp_remote_server.py          # SSH sentinel MCP server
│   ├── pyproject.toml                # Dependencies: mcp>=1.25
│   ├── setup.sh                      # One-command install for Claude Code / Codex
│   └── tests/                        # Unit tests
├── reference/
│   ├── context.template.md           # Template (distributed)
│   └── context.local.md              # Personal config (gitignored, auto-generated)
```

> **Note**: If you use Claude Code, cluster operations are automatically delegated to the `cluster-operator` subagent — no manual invocation required. This keeps your main conversation context clean.

## How the MCP Server Works

Some SSH proxies / jump hosts don't close connections after commands finish. The MCP server works around this:

```
remote_bash("nvidia-smi")

→ ssh -tt gpu-node 'nvidia-smi 2>&1; echo "___MCP_EXIT_${?}___"'

stdout:
  Thu Mar 19 ...
  | NVIDIA H100 ...
  ___MCP_EXIT_0___     ← sentinel detected

→ proc.kill()          ← force-kill SSH process
→ return clean output
```

Sentinel + `proc.kill()` = no hanging, fully automatic.

## Adapting to Your Cluster

This skill is designed to be cluster-agnostic. To adapt it to your environment:

| What | How |
|------|-----|
| SSH access | Any `ssh` command that reaches your cluster (direct, jump host, tunnel, proxy) |
| Code sync | Configure your preferred method (git, rsync, shared NFS, etc.) in `context.local.md` |
| Log/output sync | Configure your preferred method (object storage, rsync, scp, etc.) in `context.local.md` |
| Safety rules | Define protected paths and restrictions during interactive setup |
| GPU management | Optionally configure GPU idle-prevention scripts |

## Acknowledgements

Heavily inspired by [claude-code-local-for-vscode](https://github.com/justimyhxu/claude-code-local-for-vscode).

## License

MIT
