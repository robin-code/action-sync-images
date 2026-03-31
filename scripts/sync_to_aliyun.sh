#!/usr/bin/env bash

# export IMAGE_REGISTRY_NAME_SPACE=registry.cn-hangzhou.aliyuncs.com/robin-sync
set -euo pipefail
# 检查变量是否已设置
if [[ -z "${IMAGE_REGISTRY_NAME_SPACE}" ]]; then
  echo "❌ 环境变量 IMAGE_REGISTRY_NAME_SPACE 未设置。请设置为你的阿里云镜像命名空间（如 registry.cn-hangzhou.aliyuncs.com/your-namespace）"
  exit 1
fi

# 检查依赖
if ! command -v skopeo &> /dev/null; then
  echo "❌ 未找到 skopeo，请先安装后再运行"
  exit 1
fi

# 检查清单文件
if [[ ! -f "image.yaml" ]]; then
  echo "❌ 未找到 image.yaml"
  exit 1
fi

# 读取镜像列表文件
while IFS= read -r image || [[ -n "$image" ]]; do
  # 跳过空行和注释行
  if [[ -z "$image" ]] || [[ "$image" =~ ^[[:space:]]*# ]]; then
    continue
  fi

  # 要求镜像名必须带 tag
  if [[ "$image" != *:* ]]; then
    echo "⚠️ 跳过无 tag 镜像: $image"
    continue
  fi

  # 提取版本号和镜像路径
  VERSION_TAG="${image##*:}"
  IMAGE_PATH="${image%:*}"
  # 将 / 替换为 _ 以适配阿里云命名规则
  IMAGE_PATH="${IMAGE_PATH//\//_}"

  TARGET_IMAGE="${IMAGE_REGISTRY_NAME_SPACE}/${IMAGE_PATH}:${VERSION_TAG}"
  
  echo "🚀 同步镜像: $image -> $TARGET_IMAGE"
  skopeo copy "docker://$image" "docker://$TARGET_IMAGE"
done < image.yaml
