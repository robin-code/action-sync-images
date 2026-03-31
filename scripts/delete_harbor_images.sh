#!/bin/bash

set -euo pipefail

# It is recommended to set HARBOR_USER and HARBOR_PASS as environment variables
# export HARBOR_USER="your_user"
# export HARBOR_PASS="your_password"

HARBOR_USER=${HARBOR_USER:-}
HARBOR_PASS=${HARBOR_PASS:-}
HARBOR_URL=${HARBOR_URL:-"https://docker.riji.life"}
HARBOR_URL=${HARBOR_URL%/}
HARBOR_PROJECT=${HARBOR_PROJECT:-robin-public}
HARBOR_REGISTRY=${HARBOR_URL#*://}
HARBOR_REGISTRY=${HARBOR_REGISTRY%%/*}
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

fetch_digest() {
  local project=$1
  local repo_name=$2
  local tag=$3
  local repo_enc tag_enc url artifact_response response_code response_body digest

  repo_enc=$(jq -nr --arg str "$repo_name" '$str|@uri')
  tag_enc=$(jq -nr --arg str "$tag" '$str|@uri')
  url="$HARBOR_URL/api/v2.0/projects/$project/repositories/$repo_enc/artifacts/$tag_enc"
  artifact_response=$(curl -s -u "$HARBOR_USER:$HARBOR_PASS" -w "\n%{http_code}" "$url")
  response_code="${artifact_response##*$'\n'}"
  response_body="${artifact_response%$'\n'*}"

  if [[ "$response_code" -ge 200 && "$response_code" -lt 300 ]]; then
    digest=$(printf '%s' "$response_body" | jq -r '.digest')
    if [[ -n "$digest" && "$digest" != "null" ]]; then
      printf '%s' "$digest"
      return 0
    fi
  elif [[ "$response_code" -ne 404 ]]; then
    echo "❌ Failed to fetch artifact for $project/$repo_name:$tag, HTTP status code $response_code"
  fi

  return 1
}

while IFS= read -r full_image || [[ -n "$full_image" ]]; do
  # Skip empty lines and comments
  if [[ -z "$full_image" || "${full_image:0:1}" == "#" ]]; then
    continue
  fi

  # Ensure there is an explicit tag (avoid mis-parsing images without tags)
  image_basename=${full_image##*/}
  if [[ "$image_basename" != *:* ]]; then
    echo "Skipping image without tag: $full_image"
    continue
  fi

  if [[ "$full_image" == "$HARBOR_REGISTRY/"* ]]; then
    local_image_to_delete="$full_image"
  elif [[ "$full_image" == "$HARBOR_PROJECT/"* ]]; then
    local_image_to_delete="$HARBOR_REGISTRY/$full_image"
  else
    local_image_to_delete="$HARBOR_REGISTRY/$HARBOR_PROJECT/$full_image"
  fi

  image_without_registry=${local_image_to_delete#*/}
  repo=${image_without_registry%:*}
  tag=${local_image_to_delete##*:}
  project=${repo%%/*}
  name=${repo#*/}

  echo "Processing image: $project/$name:$tag"

  digest=""
  resolved_name=""
  candidate_names=("$name")
  # Harbor 中可能存在 / 与 _ 两种命名方式，尝试兼容
  if [[ "$name" == *"/"* ]]; then
    name_alt=${name//\//_}
    if [[ "$name_alt" != "$name" ]]; then
      candidate_names+=("$name_alt")
    fi
  fi

  for candidate in "${candidate_names[@]}"; do
    if digest=$(fetch_digest "$project" "$candidate" "$tag"); then
      resolved_name="$candidate"
      break
    fi
  done

  if [ -n "$digest" ]; then
    echo "Found digest: $digest, deleting..."
    name_enc=$(jq -nr --arg str "$resolved_name" '$str|@uri')
    del_response=$(curl -s -o /dev/null -w "%{http_code}" -u "$HARBOR_USER:$HARBOR_PASS" \
      -X DELETE "$HARBOR_URL/api/v2.0/projects/$project/repositories/$name_enc/artifacts/$digest")

    if [[ "$del_response" -ge 200 && "$del_response" -lt 300 ]]; then
      echo "✅ Successfully deleted: $project/$resolved_name:$tag"
    else
      echo "❌ Failed to delete: $project/$resolved_name:$tag, HTTP status code $del_response"
    fi
  else
    echo "⚠️ Tag not found: $project/$name:$tag"
    if [[ "${#candidate_names[@]}" -gt 1 ]]; then
      echo "   Checked repositories: ${candidate_names[*]}"
    fi
  fi

done < "$FILE"
