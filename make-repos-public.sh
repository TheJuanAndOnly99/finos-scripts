#!/bin/bash

## This script is used to make repositories in the organization public that are prefixed with the given prefix
ORG=""
PREFIX=""

echo "Fetching repos from org: $ORG..."

gh repo list "$ORG" --limit 1000 --json name,visibility,isPrivate -q \
  '.[] | select(.name | startswith("'"$PREFIX"'")) | {name, visibility, isPrivate}' |
jq -c '.' |
while read -r repo; do
    NAME=$(echo "$repo" | jq -r '.name')
    IS_PRIVATE=$(echo "$repo" | jq -r '.isPrivate')

    if [[ "$IS_PRIVATE" == "true" ]]; then
        echo "Making $ORG/$NAME public..."
        gh repo edit "$ORG/$NAME" \
          --visibility public \
          --accept-visibility-change-consequences \
          || echo "❌ Failed to change visibility for $ORG/$NAME"
    else
        echo "Skipping $ORG/$NAME (already public)"
    fi
done
