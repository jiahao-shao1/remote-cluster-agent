# 集群上下文配置

> 此文件由交互式 setup 自动生成为 `context.local.md`，包含你的个人集群配置。
> `context.local.md` 已被 gitignore，不会泄露你的配置。

## 集群节点

| 名称 | SSH 命令 | MCP 工具名 | 用途 |
|------|---------|-----------|------|
| train | `ssh -p 2222 gpu-node` | `mcp__cluster-train__remote_bash` | 训练 |
| eval | `ssh gpu-eval` | `mcp__cluster-eval__remote_bash` | 评估 |

## 项目路径

| 配置项 | 值 |
|--------|---|
| 本地项目路径 | `/Users/you/project` |
| 集群项目路径 | `/home/user/project` |
| 文件同步 | Mutagen `cluster-train-files` |
| 同步模式 | `two-way-safe` |
| 忽略规则 | 本地 `.gitignore` |
| 集群无外网 | 是/否 |

## 共享存储限制

| 路径 | 类型 | 限制 |
|------|------|------|
| `/shared/data/` | 团队共享存储 | **绝对不能删除或修改非自己的文件** |

## GPU 管理

如有 GPU 占用防回收需求：

| 配置项 | 值 |
|--------|---|
| 停止占用脚本 | `scripts/stop_gpu.sh` |
| 启动占用脚本 | `scripts/start_gpu.sh` |

## Mutagen 备注

| 配置项 | 值 |
|--------|---|
| 会话名 | `cluster-train-files` |
| 远端 endpoint | `gpu-node:2222:/home/user/project` |
| 重建条件 | `.gitignore` 变更后重新运行 `setup.sh add ...` |
| 额外说明 | 如需排除 checkpoint / outputs，请写入项目 `.gitignore` |

## 其他备注

（自由填写：硬件信息、特殊限制等）
