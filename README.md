# Remote Cluster Agent

![Version](https://img.shields.io/badge/version-0.1.0-blue)

English | [中文](README.zh-CN.md)

> Enable coding agents to iterate on air-gapped GPU clusters. Edit locally, execute remotely, sync automatically with Mutagen.

## Why This Exists

Many GPU clusters (private cloud, on-prem HPC, air-gapped environments) have no public internet. Running a full coding agent remotely is either impossible or painfully slow — remote file operations via MCP proxy are ~2000x slower than local ones.

This skill flips the model: **keep all read/write local, mirror the working tree with Mutagen, only send bash commands to the cluster**.

### Architecture

```
Local Machine (has internet)                GPU Cluster (no internet)
├── Coding Agent (Claude Code / Codex)      └── /path/to/project/
├── Native tools (Read/Edit/Write)              ├── training scripts
│   ~0.5ms per operation                        ├── checkpoints
├── Mutagen sync (.gitignore-driven) ⇄ working tree mirror
└── remote_bash MCP ───sentinel+kill────────> bash commands
```

### The Automation Loop

```
Edit code (local) → Mutagen mirrors changes → Run experiment (remote) → Flush sync if needed → Read synced results locally → repeat
```

- **Code editing**: Local native tools (fast, ~0.5ms)
- **File sync**: Mutagen session managed by `setup.sh add`, defaulting to `two-way-safe`
- **Ignore rules**: Loaded from the local project's `.gitignore`
- **Remote execution**: `remote_bash` MCP tool (sentinel pattern handles non-closing SSH proxies)
- **Reading results**: Read synced files locally instead of `cat` over SSH

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

### 2. Add a managed link
`setup.sh` is now a link manager with `add`, `list`, and `remove` subcommands. `add` requires an explicit local project path, registers the MCP server, and creates a Mutagen sync session named `cluster-<name>-files`.

The installer supports both Claude Code and Codex. It auto-detects the client by default; if both are installed, use `--client` to pick one explicitly.

For Claude Code:

```bash
bash /path/to/remote-cluster-agent/mcp-server/setup.sh add --client claude <name> /path/to/local/project "<ssh_cmd>" <remote_project_dir>

# Example: register two nodes + create Mutagen sessions
bash /path/to/remote-cluster-agent/mcp-server/setup.sh add --client claude train /path/to/local/project "ssh -p 2222 gpu-node" /home/user/project
bash /path/to/remote-cluster-agent/mcp-server/setup.sh add --client claude eval  /path/to/local/project "ssh gpu-eval" /data/project
```

For Codex:

```bash
bash /path/to/remote-cluster-agent/mcp-server/setup.sh add --client codex <name> /path/to/local/project "<ssh_cmd>" <remote_project_dir>

# Example: register two nodes + create Mutagen sessions
bash /path/to/remote-cluster-agent/mcp-server/setup.sh add --client codex train /path/to/local/project "ssh -p 2222 gpu-node" /home/user/project
bash /path/to/remote-cluster-agent/mcp-server/setup.sh add --client codex eval  /path/to/local/project "ssh gpu-eval" /data/project
```

Auto-detect example:

```bash
bash /path/to/remote-cluster-agent/mcp-server/setup.sh add train /path/to/local/project "ssh -p 2222 gpu-node" /home/user/project
```

Prerequisites: [uv](https://docs.astral.sh/uv/), [Mutagen](https://mutagen.io/documentation/introduction/getting-started), SSH access to the cluster, and Claude Code or Codex CLI.

If your SSH workflow relies on complex flags such as jump hosts or `ProxyCommand`, create an alias in `~/.ssh/config` and use that alias in `ssh_cmd`. Mutagen's SSH endpoints use OpenSSH host/port syntax, so the setup script can only auto-derive endpoints from simple commands like `ssh gpu-node` or `ssh -p 2222 gpu-node`.

### 3. List or remove links

```bash
# List links managed by this script
bash /path/to/remote-cluster-agent/mcp-server/setup.sh list

# Remove a link (MCP config + Mutagen session)
bash /path/to/remote-cluster-agent/mcp-server/setup.sh remove train
```

### 4. Restart your client

After installing, restart the client you use so it reloads the new MCP server:

- Claude Code: restart Claude Code
- Codex: restart the Codex CLI session

Then just describe what you want to do on the cluster.

### 5. First-time interactive setup

On first use, your agent will ask you a few questions (SSH endpoints, local/remote paths, safety rules) and generate your personal `reference/context.local.md`. This file is gitignored — your config stays private.

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
│   ├── setup.sh                      # add/list/remove link manager for Claude Code / Codex
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
| SSH access | Use an SSH command or alias that reaches your cluster. For complex SSH flags, prefer an alias in `~/.ssh/config`. |
| File sync | `setup.sh add` creates a Mutagen session from your local project root to the remote project path. |
| Ignore rules | Mutagen imports patterns from the local `.gitignore` when the session is created. If you want to exclude `.git`, add it there explicitly. |
| Safety rules | Define protected paths and restrictions during interactive setup |
| GPU management | Optionally configure GPU idle-prevention scripts |

If you update `.gitignore`, rerun `setup.sh add ...` to recreate the Mutagen session with the new ignore set. Mutagen locks ignore rules into the session at creation time.

## Acknowledgements

Heavily inspired by [claude-code-local-for-vscode](https://github.com/justimyhxu/claude-code-local-for-vscode).

## License

MIT
