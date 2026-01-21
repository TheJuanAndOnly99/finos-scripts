#!/bin/bash

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# Initialize configuration
init_config

# Script-specific configuration
TEAMS=("$FINOS_ADMINS_TEAM" "$FINOS_STAFF_TEAM")  # Default teams
REPO_FILTER="$HACKATHON_PREFIX"  # Default filter
PERMISSION="admin"  # Default permission

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--teams)
            # Parse comma-separated teams
            IFS=',' read -ra TEAMS <<< "$2"
            shift 2
            ;;
        -f|--filter)
            REPO_FILTER="$2"
            shift 2
            ;;
        -p|--permission)
            PERMISSION="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  -t, --teams TEAM1,TEAM2,...    Comma-separated list of teams to add"
            echo "  -f, --filter FILTER            Repository name filter (default: $HACKATHON_PREFIX)"
            echo "  -p, --permission PERMISSION    Permission level (default: admin)"
            echo "  -h, --help                     Show this help message"
            echo ""
            echo "Available permissions: read, triage, write, maintain, admin"
            echo "Default teams: ${TEAMS[*]}"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use -h or --help for usage information"
            exit 1
            ;;
    esac
done

log_info "Adding teams to repositories containing '$REPO_FILTER'"
log_info "Teams: ${TEAMS[*]}"
log_info "Permission: $PERMISSION"

# Get a list of repositories containing the filter
log_info "Fetching repositories in $ORG containing '$REPO_FILTER'..."
repos=$(gh repo list "$ORG" --limit $GITHUB_API_LIMIT --json name --jq ".[] | select(.name | contains(\"$REPO_FILTER\")) | .name")

# Check if any repositories were found
if [ -z "$repos" ]; then
  log_warn "No repositories found with '$REPO_FILTER' in the name."
  exit 0
fi

log_info "Found repositories: $repos"

# Loop through each repository
for repo in $repos; do
  log_info "Processing repository: $repo"

  # Loop through the teams
  for team in "${TEAMS[@]}"; do
    log_info "Checking if team $team exists in $ORG..."
    
    # Check if the team exists
    if ! check_team_exists "$team"; then
      log_warn "Team $team does not exist. Skipping."
      continue
    fi

    log_info "Ensuring $team has $PERMISSION access to $repo..."

    # Check if the team already has access
    current_permission=$(gh api "/orgs/$ORG/teams/$team/repos/$ORG/$repo" --jq '.permission' 2>/dev/null)
    
    if [ -n "$current_permission" ]; then
      if [ "$current_permission" = "$PERMISSION" ]; then
        log_info "Team $team already has '$PERMISSION' access to $repo. Skipping."
      else
        log_info "Team $team has '$current_permission' access, updating to '$PERMISSION'..."
        if gh api --method PUT "/orgs/$ORG/teams/$team/repos/$ORG/$repo" \
          --field permission="$PERMISSION" &>/dev/null; then
          log_success "Updated $team access to '$PERMISSION' on $repo!"
        else
          log_error "Failed to update $team access on $repo"
        fi
      fi
    else
      log_info "Assigning $team as $PERMISSION to $repo..."
      if gh api --method PUT "/orgs/$ORG/teams/$team/repos/$ORG/$repo" \
        --field permission="$PERMISSION" &>/dev/null; then
        log_success "$team now has $PERMISSION access to $repo!"
      else
        log_error "Failed to assign $team to $repo"
      fi
    fi
  done

  log_info "Finished processing $repo."
done

log_success "All repositories updated!"
