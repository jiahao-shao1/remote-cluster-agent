# 集群环境上下文

## 节点

统一使用 `mcp__cluster__remote_bash(node="<名称>", command="...")` 执行命令。

| 名称 | SSH 命令 | 用途 |
|------|---------|------|
| train | `ssh -p 2222 gpu-node` | 训练 |
| eval | `ssh gpu-eval` | 评估 |

默认 node 为第一个配置的节点。

## 共享存储

如果多节点共享存储（NAS、NFS 等），在此记录路径和 Agent 部署位置。

| 路径 | 说明 |
|------|------|
| `~/.mcp-agent/agent.py` | 集群端 Agent |

## 目录结构

| 路径 | 用途 | 权限 |
|------|------|------|
| `/home/user/project` | 项目代码 | 读写 |
| `/data/outputs` | 训练输出（日志、checkpoint） | 读写 |
| `/shared/data/` | 团队共享存储 | **绝对不能删除或修改非自己的文件** |

## GPU 占用管理

如有 GPU 空闲回收机制，配置防回收脚本。

| 脚本 | 用途 | 何时调用 |
|------|------|---------|
| `scripts/start_gpu.sh` | 启动 GPU 占用 | 训练结束后、不跑程序时 |
| `scripts/stop_gpu.sh` | 停止 GPU 占用 | 训练启动前，释放显存 |

## 代码同步

通过 Mutagen 实时双向同步，保存即生效。Mutagen 通过 SSH 工作，集群不需要公网。

| 配置项 | 值 |
|--------|---|
| Mutagen session 名称 | `my-project` |
| 本地目录 | `~/repo/my_project` |
| 远程目录 | `/home/user/my_project` |

详见 `MUTAGEN.md`。

## 其他备注

（自由填写：硬件信息、特殊限制、集群无公网等）
