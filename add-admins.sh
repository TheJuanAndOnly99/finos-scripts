#!/bin/bash

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# Initialize configuration
init_config

# Script-specific configuration
USERS=("${DEFAULT_ADMINS[@]}")  # Default admin users

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -u|--users)
            # Parse comma-separated users
            IFS=',' read -ra USERS <<< "$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  -u, --users USER1,USER2,...    Comma-separated list of admin users"
            echo "  -h, --help                     Show this help message"
            echo ""
            echo "Default admin users: ${DEFAULT_ADMINS[*]}"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use -h or --help for usage information"
            exit 1
            ;;
    esac
done

log_info "Adding admin users to repositories starting with '$HACKATHON_PREFIX-'"
log_info "Admin users: ${USERS[*]}"

# Fetch all repos starting with the hackathon prefix
log_info "Fetching repositories in $ORG starting with '$HACKATHON_PREFIX-'..."
REPOS=$(gh repo list "$ORG" --limit $GITHUB_API_LIMIT --json name -q ".[] | select(.name | startswith(\"$HACKATHON_PREFIX-\")) | .name")

for repo in $REPOS; do
    log_info "Processing repository: $repo"

    for username in "${USERS[@]}"; do
        log_info "Adding $username as admin to $repo"
        if gh api --method PUT "/repos/$ORG/$repo/collaborators/$username" \
            -f permission=admin --silent > /dev/null; then
            log_success "$username added as admin to $repo"
        else
            log_error "Failed to add $username to $repo"
        fi
    done

    log_info "Finished processing $repo"
done

log_success "All admin users added to repositories!"
