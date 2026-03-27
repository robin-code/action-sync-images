#!/usr/bin/env bash

#export IMAGE_REGISTRY_NAME_SPACE=registry.cn-hangzhou.aliyuncs.com/robin-sync
#echo ${IMAGE_REGISTRY_NAME_SPACE}
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

  # 提取版本号
  VERSION_TAG=$(echo "$image" | awk -F: '{print $2}')
  echo "提取出image_tag=${VERSION_TAG}"
  # 提取镜像仓库和路径，替换斜杠为下划线
  IMAGE_PATH=$(echo "$image" | awk -F: '{print $1}' | sed 's/\//_/g')
  echo "IMAGE_PATH=${IMAGE_PATH}"
  echo ${IMAGE_REGISTRY_NAME_SPACE}
  TARGET_IMAGE="${IMAGE_REGISTRY_NAME_SPACE}/${IMAGE_PATH}:${VERSION_TAG}"
  
  echo "🚀 同步镜像: $image -> $TARGET_IMAGE"
  skopeo copy docker://$image docker://$TARGET_IMAGE
done < image.yaml