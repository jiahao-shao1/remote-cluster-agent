# Remote Cluster Agent

![Version](https://img.shields.io/badge/version-0.2.0-blue)

[English](README.md) | 中文

> 让 Coding Agent 在无公网的 GPU 集群上自动迭代。本地读写，远程执行，~0.1s 延迟。

## 安装

```bash
npx skills add https://github.com/jiahao-shao1/remote-cluster-agent
```

安装后重启你的 agent，然后说"连集群"开始使用。Agent 会在首次使用时引导你完成配置（节点、路径、MCP server 安装）。

## 架构

![Architecture](docs/architecture.png)

> [交互版本](docs/architecture.html) — 点击切换 Agent 和 Sentinel 模式。

**两种执行模式**——Agent 模式快 ~10x，Sentinel 模式是自动回退：

| 模式 | 延迟 | 原理 |
|------|------|------|
| **Agent 模式** | ~0.1s | 持久 SSH 连接 → 集群端 `agent.py` → JSON-Lines 协议 |
| **Sentinel 模式** | ~1.5s | 逐命令 SSH → 哨兵模式检测 → `proc.kill()` |

```
本地机器                                  GPU 集群（不需要公网）
├── Claude Code / Codex (Read/Edit/Write)└── /path/to/project/
│   每次操作 ~0.5ms                          ├── 训练脚本
├── Mutagen 实时同步 ◄───SSH────────────► 代码 + 日志
├── remote_bash MCP ─────SSH────────────► bash 命令
│   Agent 模式: ~0.1s                       └── agent.py（持久运行）
│   Sentinel 回退: ~1.5s
└── 本地读取结果（快 ~20x）
```

### 自动化循环

```
修改代码（本地） → Mutagen 即时同步 → 跑实验（远程） → 日志同步回来 → 读结果（本地） → 循环
```

- **代码编辑**：本地原生工具（快，~0.5ms）
- **代码同步**：[Mutagen](https://mutagen.io) 实时双向同步，通过 SSH 工作（详见 [MUTAGEN.md](MUTAGEN.md)）
- **远程执行**：`remote_bash` MCP 工具——单 MCP server，通过 `node` 参数路由多节点
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

### 3. 部署集群端 Agent（可选，快 ~10x）

```bash
scp .agents/skills/remote-cluster-agent/cluster-agent/agent.py <host>:~/.mcp-agent/agent.py
```

或者重启后让 agent 来做——直接说"部署 Agent"。

不部署 Agent 也能用，只是走 Sentinel 模式（~1.5s/命令）。

### 4. 重启客户端

安装完成后重启对应客户端以加载新的 MCP server：

- Claude Code：重启 Claude Code
- Codex：重启 Codex CLI 会话

然后直接描述你想在集群上做什么。

### 5. 配置 Mutagen 同步

```bash
bash .agents/skills/remote-cluster-agent/mutagen-setup.sh gpu-node ~/repo/my_project /home/user/my_project
```

详见 [MUTAGEN.md](MUTAGEN.md)。Mutagen 完全通过 SSH 工作——集群不需要公网。

### 6. 首次交互式配置

首次使用时，agent 会问你几个问题（SSH 端点、路径、同步方式、安全限制），自动生成你的个人配置 `reference/context.local.md`。这个文件被 gitignore，你的配置不会泄露。

## 工作原理

### Agent 模式（快，~0.1s）

```
MCP Server                          集群节点
┌──────────┐   SSH 长连接           ┌────────────┐
│ AgentConn│── stdin: JSON req ───→│ agent.py   │
│ Pool     │←─ stdout: JSON resp ──│ subprocess │
│ (每个    │                       │ .run(cmd)  │
│  节点)   │                       └────────────┘
└──────────┘
```

每个节点一条 SSH 连接，通过 `ServerAliveInterval` 保活。命令以 JSON-Lines 发送，结果立即返回。

### Sentinel 模式（回退，~1.5s）

```
remote_bash("nvidia-smi")

→ ssh -tt gpu-node 'nvidia-smi 2>&1; echo "___MCP_EXIT_${?}___"'

stdout:
  | NVIDIA H100 ...
  ___MCP_EXIT_0___     ← 检测到哨兵

→ proc.kill()          ← 强杀 SSH 进程（代理不会主动关闭）
→ 返回干净输出
```

Agent 不可用时自动使用此模式。

## 文件结构

```
remote-cluster-agent/
├── SKILL.md                          # Skill 指令
├── README.md                         # 英文说明
├── README.zh-CN.md                   # 本文件
├── .gitignore                        # 排除 context.local.md 和 .venv
├── cluster-agent/
│   └── agent.py                      # 集群端 Agent（零依赖，~100 行）
├── mcp-server/
│   ├── mcp_remote_server.py          # MCP server（Agent 模式 + Sentinel 回退）
│   ├── pyproject.toml                # 依赖：mcp>=1.25
│   ├── setup.sh                      # Claude Code / Codex 一键安装
│   └── tests/                        # 单元测试
├── mutagen-setup.sh                  # Mutagen 文件同步配置脚本
├── MUTAGEN.md                        # Mutagen 同步指南
├── reference/
│   ├── context.template.md           # 配置模板
│   └── context.local.md              # 个人配置（gitignore，自动生成）
└── VERSION
```

## 配置

Skill 在首次使用时通过交互式配置生成 `reference/context.local.md`，包含：
- 集群节点（名称、SSH 命令、用途）
- 项目路径和目录结构
- 共享存储安全规则
- GPU 管理脚本
- Mutagen 同步会话

## 致谢

深受 [claude-code-local-for-vscode](https://github.com/justimyhxu/claude-code-local-for-vscode) 项目启发。

感谢 [@cherubicXN](https://github.com/cherubicXN) 实现的基于 Mutagen 的本地-集群实时同步方案。

## 许可证

MIT
