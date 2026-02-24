#!/bin/bash

set -euo pipefail

# It is recommended to set HARBOR_USER and HARBOR_PASS as environment variables
# export HARBOR_USER="your_user"
# export HARBOR_PASS="your_password"

HARBOR_USER=${HARBOR_USER:-}
HARBOR_PASS=${HARBOR_PASS:-}
HARBOR_URL=${HARBOR_URL:-"https://docker.riji.life"}
HARBOR_URL=${HARBOR_URL%/}
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
FILE="$SCRIPT_DIR/../delete-images.yaml"

if [ ! -f "$FILE" ]; then
  echo "File does not exist: $FILE"
  exit 1
fi

if [[ -z "$HARBOR_USER" || -z "$HARBOR_PASS" ]]; then
  echo "HARBOR_USER or HARBOR_PASS not set. Please export credentials before running."
  exit 1
fi

# Check if jq is installed
if ! command -v jq &> /dev/null
then
    echo "jq could not be found, please install it first."
    exit 1
fi

# Check if curl is installed
if ! command -v curl &> /dev/null
then
    echo "curl could not be found, please install it first."
    exit 1
fi

while IFS= read -r full_image || [[ -n "$full_image" ]]; do
  # Skip empty lines and comments
  if [[ -z "$full_image" || "${full_image:0:1}" == "#" ]]; then
    continue
  fi

  # Check if the image starts with the skip prefix
  if [[ "$full_image" == "docker.riji.life/robin-public/"* || "$full_image" == "registry.cn-hangzhou.aliyuncs.com/robin-public/"* ]]; then
    echo "Skipping image: $full_image (starts with docker.riji.life/robin-public/ or registry.cn-hangzhou.aliyuncs.com/robin-public/)"
    continue # Skip to the next image
  fi

  # Ensure there is an explicit tag (avoid mis-parsing images without tags)
  image_basename=${full_image##*/}
  if [[ "$image_basename" != *:* ]]; then
    echo "Skipping image without tag: $full_image"
    continue
  fi

  # If it doesn't start with the skip prefix, add the deletion prefix
  local_image_to_delete="docker.riji.life/robin-public/$full_image"

  image_without_registry=${local_image_to_delete#*/}
  repo=${image_without_registry%:*}
  tag=${local_image_to_delete##*:}
  project=${repo%%/*}
  name=${repo#*/}

  # URL encode the repository name using jq
  name_enc=$(jq -nr --arg str "$name" '$str|@uri')

  echo "Processing image: $project/$name:$tag"

  # Get artifacts and find the digest for the specific tag
  artifacts_url="$HARBOR_URL/api/v2.0/projects/$project/repositories/$name_enc/artifacts?with_tag=true"
  artifact_response=$(curl -s -u "$HARBOR_USER:$HARBOR_PASS" -w "\n%{http_code}" "$artifacts_url")
  response_code="${artifact_response##*$'\n'}"
  response_body="${artifact_response%$'\n'*}"

  if [[ "$response_code" -lt 200 || "$response_code" -ge 300 ]]; then
    echo "❌ Failed to fetch artifacts for $project/$name:$tag, HTTP status code $response_code"
    continue
  fi

  digest=$(printf '%s' "$response_body" | jq -r --arg tag "$tag" '.[] | select(.tags[]?.name == $tag) | .digest' | head -n 1)
  if [[ "$digest" == "null" ]]; then
    digest=""
  fi

  if [ -n "$digest" ]; then
    echo "Found digest: $digest, deleting..."
    del_response=$(curl -s -o /dev/null -w "%{http_code}" -u "$HARBOR_USER:$HARBOR_PASS" \
      -X DELETE "$HARBOR_URL/api/v2.0/projects/$project/repositories/$name_enc/artifacts/$digest")

    if [[ "$del_response" -ge 200 && "$del_response" -lt 300 ]]; then
      echo "✅ Successfully deleted: $project/$name:$tag"
    else
      echo "❌ Failed to delete: $project/$name:$tag, HTTP status code $del_response"
    fi
  else
    echo "⚠️ Tag not found: $project/$name:$tag"
  fi

done < "$FILE"
