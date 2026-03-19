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
| 集群项目路径 | `/home/user/project` |
| 同步方式 | git push/pull |
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

## 日志/输出同步

通过团队已有的同步方式将集群输出拉到本地，避免用 remote_bash 读大量文件。

| 配置项 | 值 |
|--------|---|
| 上传脚本（集群执行） | `scripts/sync/upload.sh` |
| 下载脚本（本地执行） | `scripts/sync/download.sh` |
| 本地输出目录 | `outputs/` |
| 默认模式 | light（排除 *.pt, *.bin, *.safetensors, *.pth） |

## 其他备注

（自由填写：硬件信息、特殊限制等）
