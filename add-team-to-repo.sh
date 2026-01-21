#!/bin/bash

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# Initialize configuration
init_config

# Script-specific configuration
TEAM="${JUDGES_TEAM}"  # Default to judges team, can be overridden
ROLE="${JUDGES_PERMISSION}"  # Default to triage permission

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--team)
            TEAM="$2"
            shift 2
            ;;
        -r|--role)
            ROLE="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  -t, --team TEAM_NAME    Team to add to repositories (default: $JUDGES_TEAM)"
            echo "  -r, --role ROLE         Permission role (default: $JUDGES_PERMISSION)"
            echo "  -h, --help             Show this help message"
            echo ""
            echo "Available roles: read, triage, write, maintain, admin"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use -h or --help for usage information"
            exit 1
            ;;
    esac
done

log_info "Adding team '$TEAM' with '$ROLE' permission to repositories containing '$HACKATHON_PREFIX'"

# Get a list of repositories containing the hackathon prefix
log_info "Fetching repositories in $ORG containing '$HACKATHON_PREFIX'..."
repos=$(gh repo list "$ORG" --limit $GITHUB_API_LIMIT --json name --jq ".[] | select(.name | contains(\"$HACKATHON_PREFIX\")) | .name")

# Check if any repositories were found
if [ -z "$repos" ]; then
  log_warn "No repositories found with '$HACKATHON_PREFIX' in the name."
  exit 0
fi

log_info "Found repositories: $repos"

# Check if the team exists
log_info "Checking if team $TEAM exists in $ORG..."
if ! check_team_exists "$TEAM"; then
  log_error "Team $TEAM does not exist. Exiting."
  exit 1
fi

log_success "Team $TEAM verified"

# Loop through each repository
for repo in $repos; do
  log_info "Processing repository: $repo"

  # Check if the team already has access
  team_access=$(gh api "/orgs/$ORG/teams/$TEAM/repos/$ORG/$repo" --jq '.permission' 2>/dev/null)

  if [[ "$team_access" == "$ROLE" ]]; then
    log_info "Team $TEAM already has '$ROLE' access to $repo. Skipping."
  else
    log_info "Updating $TEAM permission on $repo to '$ROLE'..."
    if gh api --method PUT "/orgs/$ORG/teams/$TEAM/repos/$ORG/$repo" \
      --field permission="$ROLE"; then
      log_success "Updated $TEAM access to '$ROLE' on $repo!"
    else
      log_error "Failed to update $TEAM access on $repo"
    fi
  fi

  log_info "Finished processing $repo."
done

log_success "All repositories updated!"
