# Remote Cluster Agent

![Version](https://img.shields.io/badge/version-0.1.0-blue)

[English](README.md) | 中文

> 让 Coding Agent 在无公网的 GPU 集群上自动迭代。本地读写，远程执行，用 Mutagen 自动同步工作区。

## 为什么需要这个

很多 GPU 集群（私有云、本地 HPC、隔离环境）没有公网。在远端跑完整的 Coding Agent 要么不可能，要么慢到无法忍受——通过 MCP 代理的远程文件操作比本地慢 ~2000x。

这个 skill 反转了模式：**所有读写保持本地，用 Mutagen 镜像工作区，只往集群发 bash 命令**。

### 架构

```
本地机器（有网络）                         GPU 集群（无公网）
├── Coding Agent (Claude Code / Codex)    └── /path/to/project/
├── 原生工具 (Read/Edit/Write)                ├── 训练脚本
│   每次操作 ~0.5ms                           ├── checkpoints
├── Mutagen 同步 (.gitignore 驱动) ⇄ 工作区镜像
└── remote_bash MCP ───哨兵+kill──────────> bash 命令
```

### 自动化循环

```
修改代码（本地） → Mutagen 自动镜像 → 跑实验（远程） → 需要时 flush → 在本地读同步结果 → 循环
```

- **代码编辑**：本地原生工具（快，~0.5ms）
- **文件同步**：`setup.sh add` 创建的 Mutagen 会话，默认使用 `two-way-safe`
- **忽略规则**：从本地项目 `.gitignore` 读取
- **远程执行**：`remote_bash` MCP 工具（哨兵模式处理不关连接的 SSH 代理）
- **读取结果**：直接在本地读取已同步文件，不再通过 SSH `cat` 大文件

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

### 2. 添加受管链接
`setup.sh` 现在是一个带 `add`、`list`、`remove` 子命令的链接管理器。`add` 要求显式传入本地项目路径，并同时完成 MCP 注册和 Mutagen 会话创建。

脚本同时支持 Claude Code 和 Codex。默认会自动检测；如果两者都安装了，可以用 `--client` 显式指定。

Claude Code:

```bash
bash /path/to/remote-cluster-agent/mcp-server/setup.sh add --client claude <名称> /path/to/local/project "<SSH命令>" <集群项目路径>

# 示例：注册两个节点并创建 Mutagen 会话
bash /path/to/remote-cluster-agent/mcp-server/setup.sh add --client claude train /path/to/local/project "ssh -p 2222 gpu-node" /home/user/project
bash /path/to/remote-cluster-agent/mcp-server/setup.sh add --client claude eval  /path/to/local/project "ssh gpu-eval" /data/project
```

Codex:

```bash
bash /path/to/remote-cluster-agent/mcp-server/setup.sh add --client codex <名称> /path/to/local/project "<SSH命令>" <集群项目路径>

# 示例：注册两个节点并创建 Mutagen 会话
bash /path/to/remote-cluster-agent/mcp-server/setup.sh add --client codex train /path/to/local/project "ssh -p 2222 gpu-node" /home/user/project
bash /path/to/remote-cluster-agent/mcp-server/setup.sh add --client codex eval  /path/to/local/project "ssh gpu-eval" /data/project
```

自动检测示例：

```bash
bash /path/to/remote-cluster-agent/mcp-server/setup.sh add train /path/to/local/project "ssh -p 2222 gpu-node" /home/user/project
```

前置条件：[uv](https://docs.astral.sh/uv/)、[Mutagen](https://mutagen.io/documentation/introduction/getting-started)、SSH 可访问集群、已安装 Claude Code 或 Codex CLI。

如果你的 SSH 依赖跳板机、`ProxyCommand` 或其他复杂选项，建议先在 `~/.ssh/config` 里定义一个 alias，然后把这个 alias 用在 `ssh_cmd` 里。Mutagen 的 SSH endpoint 使用 OpenSSH 的 host/port 语法，因此安装脚本只能从 `ssh gpu-node` 或 `ssh -p 2222 gpu-node` 这类简单命令里自动推导 endpoint。

### 3. 列出或删除链接

```bash
# 列出这个脚本管理的链接
bash /path/to/remote-cluster-agent/mcp-server/setup.sh list

# 删除一个链接（同时移除 MCP 配置和 Mutagen 会话）
bash /path/to/remote-cluster-agent/mcp-server/setup.sh remove train
```

### 4. 重启客户端

安装完成后重启对应客户端以加载新的 MCP server：

- Claude Code：重启 Claude Code
- Codex：重启 Codex CLI 会话

然后直接描述你想在集群上做什么。

### 5. 首次交互式配置

首次使用时，agent 会问你几个问题（SSH 端点、本地/远程路径、安全限制），自动生成你的个人配置 `reference/context.local.md`。这个文件被 gitignore，你的配置不会泄露。

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
│   ├── setup.sh                      # Claude Code / Codex 链接管理器（add/list/remove）
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
| SSH 访问 | 使用能到达集群的 `ssh` 命令或 alias。复杂参数优先放进 `~/.ssh/config`。 |
| 文件同步 | `setup.sh add` 会从本地项目根目录到集群项目路径创建 Mutagen 会话。 |
| 忽略规则 | Mutagen 在创建会话时导入本地 `.gitignore`。如果你想排除 `.git`，需要在 `.gitignore` 里显式写出。 |
| 安全规则 | 交互式配置时定义受保护的路径和限制 |
| GPU 管理 | 可选配置 GPU 防回收脚本 |

如果你更新了 `.gitignore`，需要重新运行 `setup.sh add ...` 以重建 Mutagen 会话。Mutagen 会在创建会话时锁定 ignore 规则。

## 致谢

深受 [claude-code-local-for-vscode](https://github.com/justimyhxu/claude-code-local-for-vscode) 项目启发。

## 许可证

MIT
