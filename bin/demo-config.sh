#!/bin/bash

# Example script demonstrating the new configuration system
# This shows how to use the centralized configuration and logging

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/config.sh"

# Initialize configuration (this will check auth, org, template, etc.)
init_config

# Show current configuration
show_config

# Example: List all repositories for the current hackathon
log_info "Listing all repositories for hackathon: $HACKATHON_NAME"
repos=$(gh repo list "$ORG" --limit $GITHUB_API_LIMIT --json name -q ".[] | select(.name | contains(\"$HACKATHON_PREFIX\")) | .name")

if [ -z "$repos" ]; then
    log_warn "No repositories found for hackathon '$HACKATHON_NAME'"
else
    log_info "Found $(echo "$repos" | wc -l) repositories:"
    for repo in $repos; do
        echo "  - $repo"
    done
fi

# Example: Check if specific teams exist
log_info "Checking team existence..."
teams_to_check=("$JUDGES_TEAM" "$FINOS_STAFF_TEAM" "$FINOS_ADMINS_TEAM")

for team in "${teams_to_check[@]}"; do
    if check_team_exists "$team"; then
        log_success "Team '$team' exists"
    else
        log_warn "Team '$team' does not exist"
    fi
done

log_success "Configuration system demonstration completed!"
