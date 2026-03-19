"""Remote Cluster MCP Server - Proxy command operations to remote cluster via SSH.

Designed to work with SSH proxies / jump hosts that don't close connections
after command completion. Uses sentinel-based detection to determine when commands finish.
"""

import os
import re
import select
import subprocess
import sys
import time
from typing import Annotated

from pydantic import Field
from mcp.server.fastmcp import FastMCP

SSH_CMD = os.environ.get("SSH_CMD", "ssh 127.0.0.1")  # e.g. "ssh -p 2222 gpu-node"
REMOTE_PROJECT_DIR = os.environ.get("REMOTE_PROJECT_DIR", "")

mcp = FastMCP("remote-cluster")

# Sentinel pattern for detecting command completion
_SENTINEL_RE = re.compile(rb"___MCP_EXIT_(\d+)___\r?\n?$")
_SENTINEL_STR_RE = re.compile(r"___MCP_EXIT_(\d+)___\r?\n?$")


SSH_MAX_RETRIES = int(os.environ.get("SSH_MAX_RETRIES", "3"))
SSH_RETRY_DELAY = float(os.environ.get("SSH_RETRY_DELAY", "2"))


def _ssh_exec_once(command: str, input_data: bytes | None = None, timeout: int = 120) -> tuple[str, bool]:
    """Single attempt to execute a command via SSH.

    Returns (output, success) where success means we got a sentinel back.
    """
    wrapped_cmd = f'{command} 2>&1; echo "___MCP_EXIT_${{?}}___"'

    ssh_args = SSH_CMD.split() + ["-tt", wrapped_cmd]
    proc = subprocess.Popen(
        ssh_args,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )

    # Send input data (e.g., file content for remote_write)
    if input_data is not None and proc.stdin:
        proc.stdin.write(input_data)
        proc.stdin.close()

    output = b""
    start_time = time.time()

    try:
        while time.time() - start_time < timeout:
            ready, _, _ = select.select([proc.stdout], [], [], 0.5)
            if ready:
                chunk = os.read(proc.stdout.fileno(), 65536)
                if not chunk:
                    break  # EOF
                output += chunk
                if _SENTINEL_RE.search(output):
                    break
    except Exception:
        pass
    finally:
        proc.kill()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.terminate()

    decoded = output.decode(errors="replace")
    # TTY mode (-tt) converts \n to \r\n, normalize it
    decoded = decoded.replace("\r\n", "\n")
    match = _SENTINEL_STR_RE.search(decoded)

    if match:
        exit_code = int(match.group(1))
        clean_output = decoded[: match.start()]
        if exit_code != 0:
            return f"Error (exit code {exit_code}):\n{clean_output}".strip(), True
        return clean_output, True
    else:
        return decoded, False


def ssh_exec(command: str, input_data: bytes | None = None, timeout: int = 120) -> str:
    """Execute a command on the remote cluster via SSH with automatic retry.

    Wraps the command with a sentinel echo so we can detect completion
    even when the SSH proxy doesn't close the connection.
    Retries up to SSH_MAX_RETRIES times on connection failures.
    """
    last_output = ""
    for attempt in range(SSH_MAX_RETRIES):
        result, success = _ssh_exec_once(command, input_data, timeout)
        if success:
            return result
        last_output = result
        if attempt < SSH_MAX_RETRIES - 1:
            print(f"SSH attempt {attempt + 1} failed, retrying in {SSH_RETRY_DELAY}s...", file=sys.stderr)
            time.sleep(SSH_RETRY_DELAY)

    return f"Error: SSH failed after {SSH_MAX_RETRIES} attempts. Partial output:\n{last_output}".strip()


# ---------------------------------------------------------------------------
# Internal helpers (testable without MCP protocol layer)
# ---------------------------------------------------------------------------


def _remote_bash(command: str, workdir: str = "", timeout: int = 120) -> str:
    if workdir:
        full_cmd = f"cd '{workdir}' && {command}"
    elif REMOTE_PROJECT_DIR:
        full_cmd = f"cd '{REMOTE_PROJECT_DIR}' && {command}"
    else:
        full_cmd = command
    return ssh_exec(full_cmd, timeout=timeout)


# ---------------------------------------------------------------------------
# MCP Tools
# ---------------------------------------------------------------------------


@mcp.tool()
def remote_bash(
    command: Annotated[
        str, Field(description="Shell command to execute on the remote cluster")
    ],
    workdir: Annotated[
        str,
        Field(
            description="Working directory (absolute path). Defaults to REMOTE_PROJECT_DIR."
        ),
    ] = "",
    timeout: Annotated[
        int,
        Field(
            description="Timeout in seconds. Default 120. Use longer for training (e.g., 3600)."
        ),
    ] = 120,
) -> str:
    """Execute a shell command on the remote cluster. Use longer timeout for training/experiments."""
    return _remote_bash(command, workdir, timeout)


if __name__ == "__main__":
    mcp.run(transport="stdio")
