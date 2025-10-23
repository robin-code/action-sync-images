#!/bin/bash

# It is recommended to set HARBOR_USER and HARBOR_PASS as environment variables
# export HARBOR_USER="your_user"
# export HARBOR_PASS="your_password"

HARBOR_USER=${HARBOR_USER}
HARBOR_PASS=${HARBOR_PASS}
HARBOR_URL=${HARBOR_URL:-"https://docker.riji.life"}
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
FILE="$SCRIPT_DIR/../remove-private-image.txt"

if [ ! -f "$FILE" ]; then
  echo "File does not exist: $FILE"
  exit 1
fi

# Check if jq is installed
if ! command -v jq &> /dev/null
then
    echo "jq could not be found, please install it first."
    exit 1
fi

while IFS= read -r full_image || [[ -n "$full_image" ]]; do
  # Skip empty lines and comments
  if [[ -z "$full_image" || "${full_image:0:1}" == "#" ]]; then
    continue
  fi

  image_without_registry=${full_image#*/}
  repo=${image_without_registry%:*}
  tag=${image_without_registry##*:}
  project=${repo%%/*}
  name=${repo#*/}

  # URL encode the repository name using jq
  name_enc=$(jq -nr --arg str "$name" '$str|@uri')

  echo "Processing image: $project/$name:$tag"

  # Get artifacts and find the digest for the specific tag
  digest=$(curl -s -u "$HARBOR_USER:$HARBOR_PASS" \
    "$HARBOR_URL/api/v2.0/projects/$project/repositories/$name_enc/artifacts?with_tag=true" | \
    jq -r --arg tag "$tag" '.[] | select(.tags[]?.name == $tag) | .digest')

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