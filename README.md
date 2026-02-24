# action-sync-images

用于批量同步与清理容器镜像的小型仓库，核心能力是：
- 将 `image.yaml` 中的镜像同步到阿里云镜像仓库；
- 再从阿里云同步到 Harbor；
- 按 `delete-images.yaml` 清单在 Harbor 里删除镜像。

## 功能

- **同步到阿里云**：把原始镜像地址转换成阿里云命名空间下的镜像名（`/` 替换为 `_`）。
- **同步到 Harbor**：从阿里云拉取镜像并推送到 Harbor，顺带生成/更新待同步列表。
- **Harbor 清理**：使用 Harbor API 按 tag 删除镜像。

## 原理概述

1. `image.yaml` 保存“源镜像”清单，支持注释与空行。
2. `sync_to_aliyun.sh` 读取清单，将镜像同步到 `IMAGE_REGISTRY_NAME_SPACE`。
3. `sync_to_harbor.sh` 读取清单，将阿里云镜像同步到 Harbor，并生成 `wait_to_harbor.txt`。
4. `delete_harbor_images.sh` 读取 `delete-images.yaml`，调用 Harbor API 删除匹配 tag 的镜像。

## 目录结构

- `image.yaml`：待同步镜像清单。
- `wait_to_harbor.txt`：同步到 Harbor 后记录的阿里云镜像列表（自动生成/更新）。
- `delete-images.yaml`：待删除镜像清单。
- `scripts/sync_to_aliyun.sh`：同步到阿里云。
- `scripts/sync_to_harbor.sh`：同步到 Harbor。
- `scripts/delete_harbor_images.sh`：按清单删除 Harbor 镜像。

## 使用方法

### 1) 同步到阿里云

```bash
export IMAGE_REGISTRY_NAME_SPACE=registry.cn-hangzhou.aliyuncs.com/your-namespace
./scripts/sync_to_aliyun.sh
```

### 2) 同步到 Harbor

```bash
export IMAGE_REGISTRY_NAME_SPACE=registry.cn-hangzhou.aliyuncs.com/your-namespace
export HARBOR_REGISTRY=harbor.example.com
export HARBOR_IMAGE_REGISTRY_NAME_SPACE=harbor.example.com/your-project
export HARBOR_USERNAME=your-user
export HARBOR_PASSWORD=your-pass

./scripts/sync_to_harbor.sh
```

### 3) 删除 Harbor 镜像

```bash
export HARBOR_USER=your-user
export HARBOR_PASS=your-pass
export HARBOR_URL=https://harbor.example.com

./scripts/delete_harbor_images.sh
```

## 依赖

- `skopeo`（同步镜像）
- `curl`、`jq`（调用 Harbor API 与解析 JSON）

## 环境变量说明

- **同步到阿里云**
  - `IMAGE_REGISTRY_NAME_SPACE`：阿里云镜像命名空间（必填）。
- **同步到 Harbor**
  - `HARBOR_REGISTRY`：Harbor Registry 域名（如 `harbor.example.com`）。
  - `HARBOR_IMAGE_REGISTRY_NAME_SPACE`：目标镜像命名空间（如 `harbor.example.com/your-project`）。
  - `HARBOR_USERNAME` / `HARBOR_PASSWORD`：Harbor 账号密码。
  - `IMAGE_REGISTRY_NAME_SPACE`：阿里云镜像命名空间。
- **删除 Harbor 镜像**
  - `HARBOR_USER` / `HARBOR_PASS`：Harbor 账号密码。
  - `HARBOR_URL`：Harbor 地址（默认 `https://docker.riji.life`）。

## 注意事项

- `image.yaml` 与 `delete-images.yaml` 中不要包含无 tag 的镜像（`name:tag` 形式）。
- 删除脚本会真实删除 Harbor 中的镜像，请在执行前确认清单无误。
- Harbor API 返回非 2xx 时会跳过该镜像并打印错误信息，避免误删。
