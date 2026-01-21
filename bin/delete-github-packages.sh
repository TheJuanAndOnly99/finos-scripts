#!/bin/bash

## This script is used to delete all packages of a given type from a given organization and repository

# Check if GitHub PAT is provided
if [ -z "$GITHUB_PAT" ]; then
    echo "Error: GITHUB_PAT environment variable is not set"
    echo "Please set your GitHub Personal Access Token:"
    echo "export GITHUB_PAT='your-token-here'"
    exit 1
fi

# Organization
ORG="finos"

# Repositories to clean (add as many as needed)
REPOS=("fluxnova-bpm-platform-formation" "fluxnova-feel-scala-formation" "fluxnova-bpm-release-parent-formation" "fluxnova-release-parent-formation")

# Package types to delete
PACKAGE_TYPES=("maven" "container")

# Dry-run mode: set to true to only list packages without deleting
DRY_RUN=true

for PACKAGE_TYPE in "${PACKAGE_TYPES[@]}"; do
    echo "==========================="
    echo "Processing package type: $PACKAGE_TYPE"
    echo "==========================="

    for REPO in "${REPOS[@]}"; do
        echo "Checking packages for repo: $REPO"

        PAGE=1
        PER_PAGE=100
        DELETE_CANDIDATES=0

        while true; do
            RESPONSE=$(curl -s -H "Authorization: Bearer $GITHUB_PAT" \
                -H "Accept: application/vnd.github.v3+json" \
                "https://api.github.com/orgs/$ORG/packages?package_type=$PACKAGE_TYPE&page=$PAGE&per_page=$PER_PAGE")

            # Filter packages belonging to the repo
            PACKAGES=$(echo "$RESPONSE" | jq -r ".[] | select(.repository.name==\"$REPO\") | .name")

            if [ -z "$PACKAGES" ]; then
                echo "No packages found on page $PAGE for $PACKAGE_TYPE in $REPO"
            else
                while read -r PACKAGE_NAME; do
                    DELETE_CANDIDATES=$((DELETE_CANDIDATES + 1))

                    if [ "$DRY_RUN" = true ]; then
                        echo "[DRY-RUN] Would delete $PACKAGE_TYPE package: $PACKAGE_NAME from $REPO"
                    else
                        echo "Deleting $PACKAGE_TYPE package: $PACKAGE_NAME from $REPO"
                        DELETE_RESPONSE=$(curl -s -X DELETE \
                            -H "Authorization: Bearer $GITHUB_PAT" \
                            -H "Accept: application/vnd.github.v3+json" \
                            "https://api.github.com/orgs/$ORG/packages/$PACKAGE_TYPE/$PACKAGE_NAME")

                        if [ $? -eq 0 ]; then
                            echo "Successfully deleted $PACKAGE_TYPE package: $PACKAGE_NAME"
                        else
                            echo "Failed to delete $PACKAGE_TYPE package: $PACKAGE_NAME"
                            echo "Response: $DELETE_RESPONSE"
                        fi
                    fi
                done <<< "$PACKAGES"
            fi

            TOTAL_ON_PAGE=$(echo "$RESPONSE" | jq '. | length')
            if [ "$TOTAL_ON_PAGE" -lt "$PER_PAGE" ]; then
                break
            fi

            PAGE=$((PAGE + 1))
        done

        echo "Total $PACKAGE_TYPE packages matched for $REPO: $DELETE_CANDIDATES"
    done
done

echo "Package deletion process completed (dry-run=$DRY_RUN)."