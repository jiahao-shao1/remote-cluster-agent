---
name: remote-cluster-agent
description: 远程 GPU 集群操作。当用户提到集群、远程执行、GPU、训练、同步代码时使用。触发词包括但不限于："连集群"、"同步代码"、"GPU 占用"、"集群上跑"、"remote bash"、"在服务器上"、"跑训练"、"看日志"、"tail log"。即使用户没有明确提到集群，只要任务涉及远程执行或训练相关操作，也应该触发此 skill。
---

# Remote Cluster Agent

通过 MCP server 提供 `remote_bash` 工具，在远程 GPU 集群上执行命令。

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

### 第 2 轮：安全限制 + 同步方式 + 补充（2-3 个问题）

1. **共享存储安全限制**
   - header: "安全限制"
   - 选项: "有受保护的共享路径" / "没有特殊限制" / "自定义"
   - 如果有，追问具体路径和限制规则

2. **日志/输出同步方式**
   - header: "日志同步"
   - 选项: "有同步脚本（用于同步训练输出到本地）" / "不需要同步（直接用 remote_bash 读取）"
   - 如果有，追问：上传脚本路径（集群上）、下载脚本路径（本地）、本地输出目录

3. **（条件）GPU 脚本路径**——仅当上轮选了"需要"时才问

### 生成配置 & 安装

1. 参考 `reference/context.template.md` 格式，生成 `reference/context.local.md`
2. 对每个节点运行 MCP server 安装：
   ```bash
   bash <skill_dir>/mcp-server/setup.sh <节点名> "<SSH命令>" <项目路径>
   ```
3. 提示用户重启 Claude Code 以加载新的 MCP server

## 架构原则

- **代码编辑在本地**：Coding Agent 原生工具（~0.5ms），远程 MCP 代理文件操作慢 ~2000x
- **代码同步用团队已有方式**：git push/pull、rsync、共享文件系统等
- **远程只跑命令**：通过 `remote_bash` 执行训练等 batch 操作
- **读日志/结果在本地**：通过团队已有的同步方式拉到本地，然后用原生 Read 工具读取（比 remote_bash cat 快 ~20x）

## 核心操作

以下操作中的路径均从 `reference/context.local.md` 读取，不要硬编码。

### 同步代码

```bash
# 本地（示例：git 方式）
git add <files> && git commit -m "..." && git push

# 集群 (remote_bash)
cd <project_dir> && git pull
```

验证：对比本地和集群的 `git log --oneline -1`。

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

### 同步输出到本地（读日志/结果时优先使用）

当需要读取集群上的日志、评估结果等文件时，优先通过同步方式拉到本地再用原生 Read 工具读取，速度快得多。

路径和脚本从 `context.local.md` 的同步配置读取。

```bash
# Step 1: 集群 → 中转存储（remote_bash 执行）
cd <project_dir> && bash <upload_script> [subdir]

# Step 2: 中转存储 → 本地（本地 Bash 执行）
bash <download_script> [subdir]

# Step 3: 本地 Read 工具读取
# 文件现在在 <local_outputs_dir>/ 下，直接用 Read 工具
```

**注意**：默认排除 checkpoint 文件（*.pt, *.bin, *.safetensors, *.pth），避免撑爆本地存储。只在用户明确要求时才同步大文件。

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
