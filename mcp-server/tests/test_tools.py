"""Tests for _remote_bash internal helper."""

from unittest.mock import patch

from mcp_remote_server import _remote_bash


class TestRemoteBash:
    def test_simple(self):
        with patch("mcp_remote_server.ssh_exec") as mock_ssh:
            mock_ssh.return_value = "hello\n"
            result = _remote_bash("echo hello")
            assert result == "hello\n"

    def test_with_workdir(self):
        with patch("mcp_remote_server.ssh_exec") as mock_ssh:
            mock_ssh.return_value = "/project\n"
            _remote_bash("pwd", workdir="/project")
            cmd = mock_ssh.call_args[0][0]
            assert "cd '/project'" in cmd

    def test_uses_default_project_dir(self, monkeypatch):
        monkeypatch.setattr("mcp_remote_server.REMOTE_PROJECT_DIR", "/default/project")
        with patch("mcp_remote_server.ssh_exec") as mock_ssh:
            mock_ssh.return_value = ""
            _remote_bash("ls")
            cmd = mock_ssh.call_args[0][0]
            assert "/default/project" in cmd

    def test_custom_timeout(self):
        with patch("mcp_remote_server.ssh_exec") as mock_ssh:
            mock_ssh.return_value = "done\n"
            _remote_bash("python train.py", timeout=600)
            assert mock_ssh.call_args.kwargs.get("timeout") == 600

    def test_workdir_overrides_default(self, monkeypatch):
        monkeypatch.setattr("mcp_remote_server.REMOTE_PROJECT_DIR", "/default")
        with patch("mcp_remote_server.ssh_exec") as mock_ssh:
            mock_ssh.return_value = ""
            _remote_bash("ls", workdir="/custom")
            cmd = mock_ssh.call_args[0][0]
            assert "/custom" in cmd
            assert "/default" not in cmd

    def test_no_workdir_no_project_dir(self, monkeypatch):
        monkeypatch.setattr("mcp_remote_server.REMOTE_PROJECT_DIR", "")
        with patch("mcp_remote_server.ssh_exec") as mock_ssh:
            mock_ssh.return_value = ""
            _remote_bash("whoami")
            cmd = mock_ssh.call_args[0][0]
            assert cmd == "whoami"
