---
name: remote-cluster-agent
description: 远程 GPU 集群操作。当用户提到集群、远程执行、GPU、训练、同步代码时使用。触发词包括但不限于："连集群"、"同步代码"、"GPU 占用"、"集群上跑"、"remote bash"、"在服务器上"、"跑训练"、"看日志"、"tail log"、"mutagen"。即使用户没有明确提到集群，只要任务涉及远程执行或训练相关操作，也应该触发此 skill。
---

# Remote Cluster Agent

通过单个 MCP server 提供 `remote_bash` 工具（带 `node` 参数路由），在远程 GPU 集群上执行命令。
使用持久 SSH 长连接 + 集群端 Agent 模式，命令延迟 ~0.1s（旧 sentinel 模式 ~1.5s，约 10x 加速）。

## Step 0: 检查配置

读取 `reference/context.local.md`。

- **文件存在** → 加载集群上下文，跳到「核心操作」
- **文件不存在** → 进入「首次配置」

## 首次配置

用 AskUserQuestion 收集信息，生成 `reference/context.local.md`。目标：2 轮交互完成。

### 第 1 轮：集群连接 + 项目路径（4 个问题）

同时问以下 4 个问题：

1. **节点数量**
   - header: "节点数量"
   - 选项: "1 个" / "2 个" / "3 个以上"

2. **第一个节点的 SSH 命令和名称**
   - header: "节点 1"
   - 选项带 preview 展示格式，用户通过 Other 自由输入
   - 选项示例: "ssh -p 2222 gpu-node（训练节点）" / "ssh gpu-eval（评估节点）"
   - preview 示例: `名称: train\nSSH:  ssh -p 2222 gpu-node\n用途: 训练`

3. **项目代码路径**
   - header: "项目路径"
   - 选项: "/home/user/project" / "自定义路径"

4. **GPU 占用防回收**
   - header: "GPU 占用"
   - 选项: "需要（我有 start/stop 脚本）" / "不需要"

如果用户选了 2 个以上节点，追加 1 轮问后续节点信息（同样用 preview 格式）。

### 第 2 轮：安全限制 + Mutagen + 补充（2-3 个问题）

1. **共享存储安全限制**
   - header: "安全限制"
   - 选项: "有受保护的共享路径" / "没有特殊限制" / "自定义"
   - 如果有，追问具体路径和限制规则

2. **Mutagen 文件同步**
   - header: "代码同步"
   - 选项: "已配置 Mutagen（实时同步）" / "需要帮助配置 Mutagen" / "暂不配置"
   - 如果需要帮助，引导用户参考 `MUTAGEN.md` 进行配置

3. **（条件）GPU 脚本路径**——仅当上轮选了"需要"时才问

### 生成配置 & 安装

根据交互收集的信息，执行以下步骤：

**Step 1: 生成配置文件**

参考 `reference/context.template.md` 格式，用用户回答填充，生成 `reference/context.local.md`。
注意在节点表中填入实际的节点名称和 SSH 命令。

**Step 2: 构建 NODES JSON**

将所有节点的名称和 SSH 命令组成 JSON。例如用户输入了两个节点：
```
NODES='{"train":"ssh -p 2222 gpu-node","eval":"ssh gpu-eval"}'
```

**Step 3: 安装 MCP server**

```bash
bash <skill_dir>/mcp-server/setup.sh "$NODES" <项目路径>
```

如果用户的 agent 路径不是默认的 `~/.mcp-agent/agent.py`，追加参数：
```bash
bash <skill_dir>/mcp-server/setup.sh "$NODES" <项目路径> <agent_path>
```

**Step 4: 提示重启 + 部署 Agent**

告诉用户：
1. 重启 Claude Code 以加载新的 MCP server
2. 重启后，运行以下命令部署集群端 Agent（只需做一次）：
   ```
   请说 "部署集群 Agent" 或 "deploy agent"，我会通过 remote_bash 自动完成
   ```

**Step 5: Agent 部署**（用户重启后触发）

当用户重启回来并请求部署 Agent 时：
1. 读取 `<skill_dir>/cluster-agent/agent.py` 的内容
2. 通过 `remote_bash` 写入集群：
   ```bash
   mkdir -p ~/.mcp-agent
   cat > ~/.mcp-agent/agent.py << 'AGENT_EOF'
   ... (agent.py 的完整内容)
   AGENT_EOF
   chmod +x ~/.mcp-agent/agent.py
   python3 -c "import ast; ast.parse(open(os.path.expanduser('~/.mcp-agent/agent.py')).read()); print('syntax OK')"
   ```
3. 验证 Agent 可用：
   ```bash
   echo '{"type":"ping"}' | python3 ~/.mcp-agent/agent.py
   ```
4. 提示用户再次重启 Claude Code，Agent 模式将自动启用

> 如果 Step 5 跳过，MCP server 仍然可用（自动降级为 sentinel 模式，~1.5s/命令）。
> Agent 部署后无需再次重启——下次 remote_bash 调用时会自动连接 Agent。

## 架构原则

- **代码编辑在本地**：Claude Code 原生工具（~0.5ms），远程 MCP 代理文件操作慢 ~2000x
- **远程只跑命令**：通过 `mcp__cluster__remote_bash(node="train")` 执行
- **单个 MCP 管所有节点**：`node` 参数路由（train/eval/...），扩展到 N 节点不增加 context 占用
- **Agent 模式优先**：集群上的 `agent.py` 通过 SSH 长连接通信，~0.1s/命令；不可用时自动降级为 sentinel 模式
- **代码同步用 Mutagen**：通过 SSH 隧道实时双向同步，不需要集群有公网。详见 `MUTAGEN.md`
- **读日志/结果在本地**：Mutagen 实时同步到本地后用原生 Read 工具读取（比 remote_bash cat 快 ~20x）

## 核心操作

以下操作中的路径均从 `reference/context.local.md` 读取，不要硬编码。

### 代码同步

所有环境通过 Mutagen 实时同步，保存即生效，无需手动操作。

如果 Mutagen 尚未配置，引导用户参考 `MUTAGEN.md` 进行配置。Mutagen 通过 SSH 隧道工作，集群不需要公网。

### GPU 占用管理（如果配置了）

```bash
# 释放 GPU（训练前）
bash <stop_gpu_script>

# 占用 GPU（训练后 / 空闲时）
bash <start_gpu_script>
```

### 启动训练

```bash
# remote_bash: 先停 GPU 占用（如果有），再启动训练
bash <stop_gpu_script> 2>/dev/null || true
cd <project_dir> && nohup <train_cmd> > <log_path> 2>&1 &
echo $!
```

### 检查训练状态

```bash
# remote_bash: 检查进程
ps -p <pid> -o pid,stat,etime --no-headers 2>/dev/null || echo "FINISHED"
tail -30 <log_path>

# 训练完成后重启 GPU 占用（如果有）
bash <start_gpu_script> 2>/dev/null || true
```

### 读取日志/结果

Mutagen 实时同步意味着集群上的日志/输出文件会自动出现在本地对应目录。直接用本地 Read 工具读取，无需额外同步步骤。

如果输出文件不在 Mutagen 同步范围内（如输出到了项目目录外），用 `remote_bash` 读取：
```bash
tail -100 <log_path>
```

## 安全边界

- 从 `context.local.md` 读取共享存储限制并严格遵守——共享路径下的文件可能属于其他团队，误删可能导致他们的实验中断
- 如果集群无公网，不要尝试访问外部 URL（如 GitHub、PyPI 官方源）——使用集群内部源
- 不自动 push 到 master/main——避免未经 review 的代码影响团队其他成员
- **`pkill -f` 必须用方括号技巧**：`pkill -f "[s]glang.launch_server"` 而不是 `pkill -f "sglang.launch_server"`——因为 SSH 进程的命令行参数包含被 kill 的模式，`pkill -f` 会把 SSH 自身也杀掉，导致哨兵收不到，命令卡死。同理适用于所有 `pgrep -f`、`grep` 进程列表等操作
- **长驻进程必须后台化**：remote_bash 通过哨兵检测命令完成，如果进程不退出（如推理 server、训练脚本），哨兵永远收不到，命令会卡死。必须用 `nohup ... &` 或 `tmux new-session -d`，且 `echo` 放在后台命令之后用 `;` 分隔：
  ```bash
  # 正确：nohup 后台 + echo 在外面
  nohup python -m vllm.entrypoints.openai.api_server ... > /tmp/log 2>&1 & echo "PID=$!"
  # 正确：tmux detach + echo 在外面
  tmux new-session -d -s serve "python -m vllm.entrypoints.openai.api_server ..."; echo "started"
  # 错误：echo 在 tmux 内部的 && 链里，永远执行不到
  tmux new-session -d -s serve "python ... && echo started"
  ```
