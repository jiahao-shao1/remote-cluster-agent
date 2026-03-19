# Changelog

All notable changes to this project will be documented in this file.

Format follows [Keep a Changelog](https://keepachangelog.com/), versioning follows [Semantic Versioning](https://semver.org/).

## [0.1.0] - 2026-03-19

### Added

- MCP server with sentinel-based SSH command execution for air-gapped GPU clusters
- Interactive setup flow (SSH endpoints, paths, sync methods, safety rules)
- `remote_bash` tool for running commands on cluster
- `cluster-operator` subagent for automatic delegation of cluster operations
- Configurable log/output sync support (team-owned sync methods)
- `context.template.md` for personal config generation
- One-command install script (`setup.sh`)
- Unit tests for SSH execution and tool registration
- Chinese and English README
