#!/usr/bin/env bash

set -e

# 检查变量是否已设置
if [[ -z "${IMAGE_REGISTRY_NAME_SPACE}" ]]; then
  echo "❌ 环境变量 IMAGE_REGISTRY_NAME_SPACE 未设置。请设置为你的阿里云镜像命名空间（如 registry.cn-hangzhou.aliyuncs.com/your-namespace）"
  exit 1
fi

# 读取镜像列表文件
while IFS= read -r image || [[ -n "$image" ]]; do
  # 跳过空行和注释行
  if [[ -z "$image" ]] || [[ "$image" =~ ^[[:space:]]*# ]]; then
    continue
  fi
  IMAGE_NAME=$(echo "$image" | awk -F'/' '{split($NF,a,":"); print a[1]}')
  TARGET_IMAGE="${IMAGE_REGISTRY_NAME_SPACE}/${IMAGE_NAME}"

  echo "🚀 同步镜像: $image -> $TARGET_IMAGE"
  skopeo copy docker://$image docker://$TARGET_IMAGE
done < image.txt