# Remote Cluster Agent

![Version](https://img.shields.io/badge/version-0.1.0-blue)

[English](README.md) | 中文

> 让 Coding Agent 在无公网的 GPU 集群上自动迭代。本地读写，远程执行，同步方式你说了算。

## 为什么需要这个

很多 GPU 集群（私有云、本地 HPC、隔离环境）没有公网。在远端跑完整的 Coding Agent 要么不可能，要么慢到无法忍受——通过 MCP 代理的远程文件操作比本地慢 ~2000x。

这个 skill 反转了模式：**所有读写保持本地，只往集群发 bash 命令**。

### 架构

```
本地机器（有网络）                       GPU 集群（无公网）
├── Coding Agent (Claude Code / Codex)  └── /path/to/project/
├── 原生工具 (Read/Edit/Write)              ├── 训练脚本
│   每次操作 ~0.5ms                         ├── checkpoints
├── 代码同步 (git/rsync/自定义) ──────────> pull 变更
├── remote_bash MCP ───哨兵+kill────────> bash 命令
└── 日志同步 (自定义) <───────────────────── 训练输出
```

### 自动化循环

```
修改代码（本地） → 同步代码 → 跑实验（远程） → 同步日志 → 读结果（本地） → 循环
```

- **代码编辑**：本地原生工具（快，~0.5ms）
- **代码同步**：团队已有的任何方式（git push/pull、rsync、共享文件系统等）
- **远程执行**：`remote_bash` MCP 工具（哨兵模式处理不关连接的 SSH 代理）
- **日志同步**：团队已有的任何方式（对象存储、rsync、共享文件系统等）
- **读取结果**：本地原生 Read 工具（比远程 MCP 读取快 ~20x）

## 快速开始

### 1. 安装 skill

Claude Code：

```bash
npx skills add https://github.com/jiahao-shao1/remote-cluster-agent
```

Codex：

```bash
mkdir -p ~/.codex/skills
ln -s /path/to/remote-cluster-agent ~/.codex/skills/remote-cluster-agent
```

### 2. 安装 MCP server

脚本现在同时支持 Claude Code 和 Codex。默认会自动检测；如果两者都安装了，可以用 `--client` 显式指定。

Claude Code:

```bash
bash .agents/skills/remote-cluster-agent/mcp-server/setup.sh --client claude <名称> "<SSH命令>" <集群项目路径>

# 示例：注册两个节点
bash .agents/skills/remote-cluster-agent/mcp-server/setup.sh --client claude train "ssh -p 2222 gpu-node" /home/user/project
bash .agents/skills/remote-cluster-agent/mcp-server/setup.sh --client claude eval  "ssh gpu-eval" /data/project
```

Codex:

```bash
bash .agents/skills/remote-cluster-agent/mcp-server/setup.sh --client codex <名称> "<SSH命令>" <集群项目路径>

# 示例：注册两个节点
bash .agents/skills/remote-cluster-agent/mcp-server/setup.sh --client codex train "ssh -p 2222 gpu-node" /home/user/project
bash .agents/skills/remote-cluster-agent/mcp-server/setup.sh --client codex eval  "ssh gpu-eval" /data/project
```

自动检测示例：

```bash
bash .agents/skills/remote-cluster-agent/mcp-server/setup.sh train "ssh -p 2222 gpu-node" /home/user/project
```

前置条件：[uv](https://docs.astral.sh/uv/)、SSH 可访问集群、已安装 Claude Code 或 Codex CLI。

### 3. 重启客户端

安装完成后重启对应客户端以加载新的 MCP server：

- Claude Code：重启 Claude Code
- Codex：重启 Codex CLI 会话

然后直接描述你想在集群上做什么。

### 4. 首次交互式配置

首次使用时，agent 会问你几个问题（SSH 端点、路径、同步方式、安全限制），自动生成你的个人配置 `reference/context.local.md`。这个文件被 gitignore，你的配置不会泄露。

## 文件结构

```
remote-cluster-agent/
├── SKILL.md                          # Skill 指令（通用，无个人信息）
├── README.md                         # 英文说明
├── README.zh-CN.md                   # 本文件
├── .gitignore                        # 排除 context.local.md 和 .venv
├── .claude/
│   └── agents/
│       └── cluster-operator.md       # 集群操作 sub-agent（自动调度）
├── mcp-server/
│   ├── mcp_remote_server.py          # SSH 哨兵 MCP server
│   ├── pyproject.toml                # 依赖：mcp>=1.25
│   ├── setup.sh                      # Claude Code / Codex 一键安装
│   └── tests/                        # 单元测试
├── reference/
│   ├── context.template.md           # 模板（随 skill 分发）
│   └── context.local.md              # 个人配置（gitignore，自动生成）
```

> **说明**：如果你使用 Claude Code，当需要执行集群操作时，它会自动将任务委托给 `cluster-operator` sub-agent，无需手动调用。这样可以保持主对话上下文干净。

## MCP Server 工作原理

有些 SSH 代理 / 跳板机在命令执行完后不关闭连接。MCP server 的处理方式：

```
remote_bash("nvidia-smi")

→ ssh -tt gpu-node 'nvidia-smi 2>&1; echo "___MCP_EXIT_${?}___"'

stdout:
  Thu Mar 19 ...
  | NVIDIA H100 ...
  ___MCP_EXIT_0___     ← 检测到哨兵

→ proc.kill()          ← 强杀 SSH 进程
→ 返回干净输出
```

哨兵 + `proc.kill()` = 不挂起，全自动。

## 适配你的集群

这个 skill 设计为集群无关。适配你的环境只需：

| 配置项 | 方式 |
|--------|------|
| SSH 访问 | 任何能到达集群的 `ssh` 命令（直连、跳板机、隧道、代理） |
| 代码同步 | 在 `context.local.md` 中配置你的方式（git、rsync、NFS 等） |
| 日志/输出同步 | 在 `context.local.md` 中配置你的方式（对象存储、rsync、scp 等） |
| 安全规则 | 交互式配置时定义受保护的路径和限制 |
| GPU 管理 | 可选配置 GPU 防回收脚本 |

## 致谢

深受 [claude-code-local-for-vscode](https://github.com/justimyhxu/claude-code-local-for-vscode) 项目启发。

## 许可证

MIT
