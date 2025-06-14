#!/usr/bin/env bash

# 检查是否有需要同步的镜像
need_sync_count=$(grep -v '^[[:space:]]*#' image.txt | grep -v '^[[:space:]]*$' | wc -l)
if [[ "$need_sync_count" -eq 0 ]]; then
  echo "✅ 没有需要同步的镜像，流水线终止"
  exit 1
fi

set -e

# 登录到Harbor
if [[ -n "${HARBOR_USERNAME}" ]] && [[ -n "${HARBOR_PASSWORD}" ]]; then
  echo "🔑 登录到Harbor..."
  skopeo login --username "${HARBOR_USERNAME}" --password "${HARBOR_PASSWORD}" "${HARBOR_REGISTRY}"
else
  echo "⚠️ 未提供Harbor凭据"
  exit 1
fi

# 读取镜像列表文件
while IFS= read -r image || [[ -n "$image" ]]; do
  # 跳过空行和注释行
  if [[ -z "$image" ]] || [[ "$image" =~ ^[[:space:]]*# ]]; then
    continue
  fi

  # 提取版本号 - 不使用awk
  VERSION_TAG=${image##*:}
  
  # 提取镜像仓库和路径，替换斜杠为下划线 - 不使用awk
  IMAGE_PATH=${image%:*}
  IMAGE_PATH=${IMAGE_PATH//\//_}
  
  TARGET_IMAGE="${IMAGE_REGISTRY_NAME_SPACE}/${IMAGE_PATH}:${VERSION_TAG}"

  HARBOR_IMAGE="${HARBOR_IMAGE_REGISTRY_NAME_SPACE}/${image}"


  echo "🚀 同步镜像: $image -> $TARGET_IMAGE -> $HARBOR_IMAGE"
  skopeo copy docker://$image docker://$HARBOR_IMAGE
done < image.txt

echo "✅ 所有镜像同步完成!"