#!/usr/bin/env bash

mkdir -p /data
set -e

# 创建一个临时文件来存储阿里云镜像列表
TMP_FILE=$(mktemp)
# 确保在脚本退出时删除临时文件
trap 'rm -f "$TMP_FILE"' EXIT

# 检查是否有需要同步的镜像
need_sync_count=$(grep -v '^[[:space:]]*#' image.yaml | grep -v '^[[:space:]]*$' | wc -l)
if [[ "$need_sync_count" -eq 0 ]]; then
  echo "✅ 没有需要同步的镜像，流水线终止"
  # 确保 wait_to_harbor.txt 为空
  > wait_to_harbor.txt
  echo "none" > /data/sync_result.txt
  exit 0
fi

## 登录到Harbor
if [[ -n "${HARBOR_USERNAME}" ]] && [[ -n "${HARBOR_PASSWORD}" ]]; then
  echo "🔑 登录到Harbor..."
  skopeo login --username "${HARBOR_USERNAME}" --password "${HARBOR_PASSWORD}" "${HARBOR_REGISTRY}"
else
  echo "⚠️ 未提供Harbor凭据，无法登录"
  exit 1
fi

# 读取原始镜像列表文件
while IFS= read -r image || [[ -n "$image" ]]; do
  # 跳过空行和注释行
  if [[ -z "$image" ]] || [[ "$image" =~ ^[[:space:]]*# ]]; then
    continue
  fi

  # --- 计算阿里云和Harbor的镜像地址 ---
  # 提取版本号
  VERSION_TAG=${image##*:}
  # 提取镜像路径
  IMAGE_PATH=${image%:*}
  
  # 计算阿里云的镜像路径 (将 / 替换为 _)
  IMAGE_PATH_ALIYUN=${IMAGE_PATH//\//_}
  ALIYUN_IMAGE="${IMAGE_REGISTRY_NAME_SPACE}/${IMAGE_PATH_ALIYUN}:${VERSION_TAG}"
  
  # 计算Harbor的镜像地址 (使用原始镜像名)
  HARBOR_IMAGE="${HARBOR_IMAGE_REGISTRY_NAME_SPACE}/${image}"

  # --- 执行同步 ---
  echo "🚀 同步镜像: $ALIYUN_IMAGE -> $HARBOR_IMAGE"
  skopeo copy "docker://$ALIYUN_IMAGE" "docker://$HARBOR_IMAGE"
  
  # --- 记录已同步的阿里云镜像地址 ---
  echo "$ALIYUN_IMAGE" >> "$TMP_FILE"

done < image.yaml

# --- 完成后处理 ---
# 将临时文件的内容追加到最终的输出文件
cat "$TMP_FILE" >> wait_to_harbor.txt

# 对文件进行排序和去重，确保唯一性
sort -u wait_to_harbor.txt -o wait_to_harbor.txt

echo "✅ 所有镜像同步完成! 待同步列表已更新到 wait_to_harbor.txt"
echo "success" > /data/sync_result.txt
