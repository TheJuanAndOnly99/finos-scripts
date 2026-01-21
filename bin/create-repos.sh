#!/bin/bash

# This script is used to create repositories for hackathon teams.

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/config.sh"

# Initialize configuration
init_config

# Team names for the hackathon
REPOS=(
  "Akaza"
  "Hello Worlders"
  "Shivam Dubey"
  "Shoaib Akhtar"
  "Synapse"
  "RagDoll"
  "CodeHub"
  "HackerLog"
  "Innouvetta"
  "Solution Makers"
  "The Knights Templar"
  "Project genesis"
  "RagDoll"
  "CodeByte"
  "LMNTRX"
  "Arion"
  "virtusa"
  "FeedForward"
  "HackerLog"
  "ProctoBots"
  "RagDoll"
  "AIB"
  "LMNTRX"
  "HackFusion"
  "Unicoding"
  "Arion"
  "UG26"
  "AtomX"
  "Cucumber Town"
  "Incognito"
  "solutionmakers"
  "Crabs"
  "Hackaholics"
  "Error403"
  "Team Alpha"
  "Innovators"
  "Devign"
  "TempName"
  "Vyakayan"
  "Cheque mates"
)

# Script-specific configuration
DRY_RUN=true
SKIP_EXISTING=true

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        --no-skip-existing)
            SKIP_EXISTING=false
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  -d, --dry-run              Show what would be done without making changes"
            echo "  --no-skip-existing         Don't skip repositories that already exist"
            echo "  -h, --help                 Show this help message"
            echo ""
            echo "This script creates repositories for hackathon teams using the template:"
            echo "  Template: $ORG/$TEMPLATE_REPO"
            echo "  Prefix: $HACKATHON_PREFIX"
            echo "  Teams: ${#REPOS[@]} teams"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use -h or --help for usage information"
            exit 1
            ;;
    esac
done

log_info "Starting repository creation for hackathon: $HACKATHON_NAME"
log_info "Template: $ORG/$TEMPLATE_REPO"
log_info "Teams to process: ${#REPOS[@]}"
if [ "$DRY_RUN" = true ]; then
    log_warn "DRY RUN MODE - No changes will be made"
fi

for REPO in "${REPOS[@]}"; do
  TEAM_SLUG=$(slugify "$REPO")
  REPO_SLUG="${HACKATHON_PREFIX}-${TEAM_SLUG}"
  TEAM_NAME="${REPO_SLUG}-team"

  log_info "Processing: $REPO_SLUG | Team: $TEAM_NAME"

  # Check if repository already exists
  if gh api "/repos/$ORG/$REPO_SLUG" &>/dev/null; then
    if [ "$SKIP_EXISTING" = true ]; then
      log_warn "Repository $REPO_SLUG already exists. Skipping."
      continue
    else
      log_warn "Repository $REPO_SLUG already exists. Continuing anyway."
    fi
  fi

  # Create repository from template
  if [ "$DRY_RUN" = true ]; then
    log_info "[DRY RUN] Would create repository: $ORG/$REPO_SLUG from template $ORG/$TEMPLATE_REPO"
  else
    log_info "Creating repository $REPO_SLUG from template as $DEFAULT_VISIBILITY..."
    if gh repo create "$ORG/$REPO_SLUG" \
      --template "$ORG/$TEMPLATE_REPO" \
      --$DEFAULT_VISIBILITY \
      --confirm; then
      log_success "Repository $REPO_SLUG created successfully"
    else
      log_error "Failed to create repository $REPO_SLUG"
      continue
    fi
  fi

  # Set branch protection
  if [ "$DRY_RUN" = true ]; then
    log_info "[DRY RUN] Would set branch protection on 'main' for $REPO_SLUG"
  else
    log_info "Setting branch protection on 'main'..."
    if echo "$BRANCH_PROTECTION_JSON" | gh api -X PUT "repos/$ORG/$REPO_SLUG/branches/main/protection" \
      -H "Accept: application/vnd.github+json" \
      --input - &>/dev/null; then
      log_success "Branch protection applied to $REPO_SLUG"
    else
      log_warn "Could not apply branch protection to $REPO_SLUG (branch may not exist yet)"
    fi
  fi

  # Create team if it doesn't exist
  log_info "Checking if team $TEAM_NAME exists..."
  if ! check_team_exists "$TEAM_NAME"; then
    if [ "$DRY_RUN" = true ]; then
      log_info "[DRY RUN] Would create team: $TEAM_NAME"
    else
      log_info "Creating team $TEAM_NAME..."
      if gh api -X POST "orgs/$ORG/teams" \
        -f name="$TEAM_NAME" \
        -f privacy="closed" &>/dev/null; then
        log_success "Team $TEAM_NAME created successfully"
      else
        log_error "Failed to create team $TEAM_NAME"
        continue
      fi
    fi
  else
    log_info "Team $TEAM_NAME already exists"
  fi

  # Grant team admin access to repository
  if [ "$DRY_RUN" = true ]; then
    log_info "[DRY RUN] Would grant team $TEAM_NAME '$TEAM_PERMISSION' access to $REPO_SLUG"
  else
    log_info "Granting team $TEAM_NAME '$TEAM_PERMISSION' access..."
    if gh api -X PUT "orgs/$ORG/teams/$TEAM_NAME/repos/$ORG/$REPO_SLUG" -f permission="$TEAM_PERMISSION" &>/dev/null; then
      log_success "Team $TEAM_NAME granted '$TEAM_PERMISSION' access to $REPO_SLUG"
    else
      log_error "Failed to grant team access to $REPO_SLUG"
    fi
  fi

  # Add FINOS staff teams
  for team in "$FINOS_STAFF_TEAM" "$FINOS_ADMINS_TEAM"; do
    if check_team_exists "$team"; then
      permission=""
      case "$team" in
        "$FINOS_STAFF_TEAM") permission="$STAFF_PERMISSION" ;;
        "$FINOS_ADMINS_TEAM") permission="$ADMINS_PERMISSION" ;;
      esac
      
      if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would add '$team' team with '$permission' access to $REPO_SLUG"
      else
        log_info "Adding '$team' team with '$permission' access..."
        if gh api -X PUT "orgs/$ORG/teams/$team/repos/$ORG/$REPO_SLUG" -f permission="$permission" &>/dev/null; then
          log_success "Added '$team' team with '$permission' access to $REPO_SLUG"
        else
          log_error "Failed to add '$team' team to $REPO_SLUG"
        fi
      fi
    else
      log_warn "Team '$team' does not exist, skipping"
    fi
  done

  # Add judges team
  if check_team_exists "$JUDGES_TEAM"; then
    if [ "$DRY_RUN" = true ]; then
      log_info "[DRY RUN] Would add '$JUDGES_TEAM' team with '$JUDGES_PERMISSION' access to $REPO_SLUG"
    else
      log_info "Adding '$JUDGES_TEAM' team with '$JUDGES_PERMISSION' access..."
      if gh api -X PUT "orgs/$ORG/teams/$JUDGES_TEAM/repos/$ORG/$REPO_SLUG" -f permission="$JUDGES_PERMISSION" &>/dev/null; then
        log_success "Added '$JUDGES_TEAM' team with '$JUDGES_PERMISSION' access to $REPO_SLUG"
      else
        log_error "Failed to add '$JUDGES_TEAM' team to $REPO_SLUG"
      fi
    fi
  else
    log_warn "Judges team '$JUDGES_TEAM' does not exist, skipping"
  fi

  # Remove user from team
  if [ "$DRY_RUN" = true ]; then
    log_info "[DRY RUN] Would remove user $REMOVE_USER from team $TEAM_NAME"
  else
    log_info "Removing user $REMOVE_USER from team $TEAM_NAME..."
    if gh api -X DELETE "orgs/$ORG/teams/$TEAM_NAME/memberships/$REMOVE_USER" &>/dev/null; then
      log_success "Removed $REMOVE_USER from team $TEAM_NAME"
    else
      log_warn "Could not remove $REMOVE_USER from team $TEAM_NAME (may not be a member)"
    fi
  fi

  log_success "Completed processing for $REPO_SLUG"
  echo ""
done

log_success "Repository creation process completed!"
