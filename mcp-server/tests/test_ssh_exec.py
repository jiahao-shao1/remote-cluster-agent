"""Tests for ssh_exec - the core SSH execution helper."""

import subprocess
from unittest.mock import patch, MagicMock, PropertyMock
import io
import os

from mcp_remote_server import ssh_exec


def _make_popen_mock(stdout_data: bytes, exit_code: int = 0):
    """Create a mock Popen that simulates sentinel-wrapped SSH output."""
    sentinel = f"___MCP_EXIT_{exit_code}___\n".encode()
    full_output = stdout_data + sentinel

    mock_proc = MagicMock()
    mock_proc.stdout = MagicMock()
    mock_proc.stdout.fileno.return_value = 99
    mock_proc.stdin = MagicMock()
    mock_proc.kill = MagicMock()
    mock_proc.wait = MagicMock()
    mock_proc.terminate = MagicMock()

    return mock_proc, full_output


@patch("mcp_remote_server.os.read")
@patch("mcp_remote_server.select.select")
@patch("mcp_remote_server.subprocess.Popen")
def test_ssh_exec_success(mock_popen, mock_select, mock_read):
    mock_proc, full_output = _make_popen_mock(b"hello world\n")
    mock_popen.return_value = mock_proc
    mock_select.return_value = ([mock_proc.stdout], [], [])
    mock_read.return_value = full_output

    result = ssh_exec("echo hello world")
    assert result == "hello world\n"
    mock_proc.kill.assert_called_once()


@patch("mcp_remote_server.os.read")
@patch("mcp_remote_server.select.select")
@patch("mcp_remote_server.subprocess.Popen")
def test_ssh_exec_command_failure(mock_popen, mock_select, mock_read):
    mock_proc, full_output = _make_popen_mock(b"No such file or directory\n", exit_code=1)
    mock_popen.return_value = mock_proc
    mock_select.return_value = ([mock_proc.stdout], [], [])
    mock_read.return_value = full_output

    result = ssh_exec("cat /nonexistent")
    assert "Error" in result
    assert "exit code 1" in result
    assert "No such file" in result


@patch("mcp_remote_server.os.read")
@patch("mcp_remote_server.select.select")
@patch("mcp_remote_server.subprocess.Popen")
def test_ssh_exec_no_output_command(mock_popen, mock_select, mock_read):
    """Commands with no output (like mkdir) should return empty string."""
    mock_proc, full_output = _make_popen_mock(b"")
    mock_popen.return_value = mock_proc
    mock_select.return_value = ([mock_proc.stdout], [], [])
    mock_read.return_value = full_output

    result = ssh_exec("mkdir -p /tmp/test")
    assert result == ""


@patch("mcp_remote_server.time.sleep")
@patch("mcp_remote_server.time.time")
@patch("mcp_remote_server.os.read")
@patch("mcp_remote_server.select.select")
@patch("mcp_remote_server.subprocess.Popen")
def test_ssh_exec_timeout(mock_popen, mock_select, mock_read, mock_time, mock_sleep):
    """If no sentinel is received within timeout, return error after retries."""
    mock_proc = MagicMock()
    mock_proc.stdout = MagicMock()
    mock_proc.stdout.fileno.return_value = 99
    mock_proc.kill = MagicMock()
    mock_proc.wait = MagicMock()
    mock_popen.return_value = mock_proc

    # Each retry: time() for start, time() for loop check (exceeds timeout)
    # 3 retries = 6 time() calls
    mock_time.side_effect = [0, 200, 0, 200, 0, 200]
    mock_select.return_value = ([], [], [])

    result = ssh_exec("sleep 100", timeout=10)
    assert "failed after" in result.lower()


@patch("mcp_remote_server.os.read")
@patch("mcp_remote_server.select.select")
@patch("mcp_remote_server.subprocess.Popen")
def test_ssh_exec_with_input_data(mock_popen, mock_select, mock_read):
    """Test that input_data is sent to stdin."""
    mock_proc, full_output = _make_popen_mock(b"")
    mock_popen.return_value = mock_proc
    mock_select.return_value = ([mock_proc.stdout], [], [])
    mock_read.return_value = full_output

    result = ssh_exec("cat > /tmp/file", input_data=b"file content")
    mock_proc.stdin.write.assert_called_once_with(b"file content")
    mock_proc.stdin.close.assert_called_once()


@patch("mcp_remote_server.os.read")
@patch("mcp_remote_server.select.select")
@patch("mcp_remote_server.subprocess.Popen")
def test_ssh_exec_wraps_command_with_sentinel(mock_popen, mock_select, mock_read):
    """Verify the command is wrapped with sentinel echo."""
    mock_proc, full_output = _make_popen_mock(b"ok\n")
    mock_popen.return_value = mock_proc
    mock_select.return_value = ([mock_proc.stdout], [], [])
    mock_read.return_value = full_output

    ssh_exec("whoami")

    call_args = mock_popen.call_args[0][0]
    # SSH_CMD.split() + ["-tt", wrapped_cmd], so wrapped_cmd is the last element
    cmd_str = call_args[-1]
    assert "___MCP_EXIT_" in cmd_str
    assert "whoami" in cmd_str


@patch("mcp_remote_server.os.read")
@patch("mcp_remote_server.select.select")
@patch("mcp_remote_server.subprocess.Popen")
def test_ssh_exec_uses_ssh_cmd(mock_popen, mock_select, mock_read, monkeypatch):
    """Verify SSH_CMD is split into args correctly."""
    monkeypatch.setattr("mcp_remote_server.SSH_CMD", "ssh -p 2222 gpu-node")
    mock_proc, full_output = _make_popen_mock(b"ok\n")
    mock_popen.return_value = mock_proc
    mock_select.return_value = ([mock_proc.stdout], [], [])
    mock_read.return_value = full_output

    ssh_exec("whoami")

    call_args = mock_popen.call_args[0][0]
    assert call_args[0] == "ssh"
    assert "-p" in call_args
    assert "2222" in call_args
    assert "gpu-node" in call_args
    assert "-tt" in call_args
