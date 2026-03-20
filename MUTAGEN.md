# Mutagen File Sync

Real-time bidirectional file sync between your local machine and remote GPU cluster, using [Mutagen](https://mutagen.io). Works entirely over SSH — no public internet required on the cluster.

## Why Mutagen?

Without Mutagen, you need to manually sync code for every change. Mutagen provides **real-time file sync** — save a file locally and it appears on the cluster within seconds. No commits, no push/pull.

## The Challenge

Some SSH proxies / jump hosts have issues that break Mutagen out of the box:

1. **Connections don't close** after commands finish — Mutagen's SCP-based agent installation hangs forever
2. **stderr is merged into stdout** — Mutagen agent's log messages corrupt the binary protocol handshake

The included `mutagen-setup.sh` script solves both by pre-installing the agent via stdin pipe and wrapping it to redirect stderr.

## Quick Start

### Prerequisites

1. **Mutagen** installed locally:
   ```bash
   brew install mutagen    # macOS
   # or see https://mutagen.io/documentation/introduction/installation
   ```
2. **SSH access** to cluster established (direct, tunnel, or jump host)
3. **SSH host** configured in `~/.ssh/config`, e.g.:
   ```
   Host gpu-node
       HostName 192.168.1.100
       User root
       Port 22
   ```

### Install & Sync

```
Usage: bash mutagen-setup.sh <ssh_host> <local_dir> <remote_dir> [session_name] [ignores...]

Arguments:
  ssh_host       SSH host alias from ~/.ssh/config (e.g. "gpu-node")
  local_dir      Local project directory (e.g. "~/repo/my_project")
  remote_dir     Remote project directory (e.g. "/home/user/my_project")
  session_name   (Optional) Mutagen session name. Defaults to directory basename
  ignores        (Optional) Extra directories/patterns to ignore, space-separated
```

```bash
# Basic — sync a project with default settings
bash mutagen-setup.sh gpu-node ~/repo/my_project /home/user/my_project

# With custom session name and extra ignores for large directories
bash mutagen-setup.sh gpu-node ~/repo/my_project /home/user/my_project my-sync output wandb data logs
```

The script will:
1. Detect the remote platform architecture
2. Extract and upload the Mutagen agent binary (via stdin pipe, bypassing SCP)
3. Verify the upload with checksum comparison
4. Create a stderr-redirecting wrapper (fixes the protocol corruption)
5. Create a Mutagen sync session with sensible defaults

### Default Ignores

The following patterns are always ignored:

| Pattern | Reason |
|---------|--------|
| `.git` | Git history — sync code, not repo metadata |
| `__pycache__`, `*.pyc` | Python bytecode |
| `*.pt`, `*.pth`, `*.bin`, `*.safetensors`, `*.ckpt` | Model checkpoints (often GBs) |
| `.venv` | Virtual environments |
| `*.egg-info`, `node_modules` | Package metadata |
| `.DS_Store` | macOS artifacts |

Add extra ignores as positional arguments (e.g., `output wandb data logs`).

## Important Notes

### Symlinks

If your remote path is a symlink, **use the resolved path**:

```bash
# Check the real path
ssh gpu-node "readlink -f /root/my_project"
# /data/projects/my_project  ← use this

# Use the resolved path
bash mutagen-setup.sh gpu-node ~/repo/my_project /data/projects/my_project
```

### After Mutagen Upgrades

When you upgrade Mutagen (`brew upgrade mutagen`), the agent version on the remote becomes stale. Simply re-run the script — it will detect the version mismatch and reinstall.

### Debugging

Agent logs are written to `/tmp/mutagen-agent.log` on the remote:

```bash
ssh <host> "tail -20 /tmp/mutagen-agent.log"
```

### No Public Internet Required

Mutagen works entirely over SSH. As long as your local machine can SSH into the cluster (directly or through a tunnel/jump host), Mutagen will work. The cluster does not need any outbound internet access.

## Managing Sync Sessions

```bash
# Check status
mutagen sync list

# Watch sync in real-time
mutagen sync monitor <session_name>

# Pause/resume
mutagen sync pause <session_name>
mutagen sync resume <session_name>

# Remove session
mutagen sync terminate <session_name>
```

## How It Works

### Normal Mutagen Flow (may fail through some SSH proxies)

```
mutagen sync create
  → SCP agent binary to remote      ← HANGS (proxy doesn't close connections)
  → SSH exec agent                   ← Agent logs corrupt stdout (proxy merges stderr)
  → Protocol handshake               ← FAILS (garbage bytes in stream)
```

### Our Workaround

```
mutagen-setup.sh
  → Upload agent via: cat binary | ssh host "cat > file"    ← Bypasses SCP
  → Wrapper script: exec agent-real "$@" 2>/dev/null         ← Isolates stderr
  → mutagen sync create                                      ← Works!
      → SSH exec wrapper → agent (clean stdout)
      → Magic number handshake ✓
      → Version handshake ✓
      → Bidirectional sync active
```

The key insight: Mutagen's **long-lived agent communication** (stdin/stdout pipes) works perfectly through SSH proxies — the persistent connection is actually desired. Only the **installation** (SCP) and **stderr pollution** needed workarounds.
