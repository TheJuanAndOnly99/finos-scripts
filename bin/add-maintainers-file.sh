#!/bin/bash

# This script is used to add a MAINTAINERS.md file to all repositories in the organization
# The MAINTAINERS.md file lists all repository maintainers
# The maintainers are determined from:
# - Users with \`maintain\` role on the repository
# - Teams with \`maintain\` role on the repository (excluding FINOS organization teams)
# The maintainers are listed in the MAINTAINERS.md file with their GitHub username, name, and email from their GitHub profile.

# The script creates a PR to add the MAINTAINERS.md file to the repository
# The PR is created with the title "Add MAINTAINERS.md file"
# The PR is created with the body "This PR adds a MAINTAINERS.md file listing all repository maintainers.... (see below for more details)"

# Organizations to process
ORGS=("finos")

# Branch and PR settings
BRANCH_NAME="add-maintainers-file"
PR_TITLE="Add MAINTAINERS.md file"
PR_BODY="This PR adds a MAINTAINERS.md file listing all repository maintainers.

The maintainers are determined from:
- Users with \`maintain\` role on the repository
- Teams with \`maintain\` role on the repository (excluding FINOS organization teams)

Each maintainer entry includes their GitHub username, name, and email from their GitHub profile.

## Review Request

Please review this PR and:
1. **Verify the maintainer list is complete and accurate**
2. **Check that all maintainer details (name, email) are correct**
3. **Update any incorrect information** (names, emails, etc.)**
4. **If there are any missing maintainers** who should be included but were not automatically detected or if any maintainers are missing from the list, please email help@finos.org

## Sub-Repository Note

If this repository is a sub-repository of another main repository and the maintainers are the same, you can edit the MAINTAINERS.md file to simply point to the main repository's MAINTAINERS.md file instead of duplicating the list. For example:

\`\`\`markdown
# Maintainers

See the main [MAINTAINERS.md](https://github.com/org/main-repo/blob/main/MAINTAINERS.md) file.
\`\`\`

If you notice any issues or missing information, please either:
- Comment on this PR with the corrections, or
- Make the changes directly to this branch

Thank you for your review!"

# Script-specific configuration
DRY_RUN=true
SKIP_EXISTING_PR=true
TEST_REPO="finos/software-project-blueprint"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -r|--repo)
            TEST_REPO="$2"
            shift 2
            ;;
        --no-skip-existing-pr)
            SKIP_EXISTING_PR=false
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  -d, --dry-run              Show what would be done without making changes"
            echo "  -r, --repo REPO            Test on a single repository (format: org/repo-name)"
            echo "  --no-skip-existing-pr      Don't skip repos that already have an open PR"
            echo "  -h, --help                 Show this help message"
            echo ""
            echo "This script creates PRs to add MAINTAINERS.md files to all FINOS repos."
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use -h or --help for usage information"
            exit 1
            ;;
    esac
done

# Load logging functions from config if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME=$(basename "${BASH_SOURCE[0]}" .sh)
if [ -f "$SCRIPT_DIR/../lib/config.sh" ]; then
    source "$SCRIPT_DIR/../lib/config.sh"
    # Override log file name to be dynamic based on script name
    export LOG_DIR="${LOG_DIR:-./logs}"
    mkdir -p "$LOG_DIR"
    export LOG_FILE="${LOG_DIR}/${SCRIPT_NAME}-$(date '+%Y%m%d').log"
else
    # Fallback logging functions if config.sh doesn't exist
    log_info() { echo "[INFO] $1"; }
    log_warn() { echo "[WARN] $1"; }
    log_error() { echo "[ERROR] $1"; }
    log_success() { echo "[SUCCESS] $1"; }
    check_github_auth() {
        if ! gh auth status &>/dev/null; then
            log_error "GitHub CLI is not authenticated. Please run 'gh auth login' first."
            exit 1
        fi
    }
    # Fallback for GITHUB_API_LIMIT if config.sh doesn't exist
    export GITHUB_API_LIMIT="${GITHUB_API_LIMIT:-1000}"
fi

# Check GitHub auth
check_github_auth

# Get current user
CURRENT_USER=$(gh api user --jq '.login' 2>/dev/null || echo "")

# Track repos with insufficient access
INSUFFICIENT_ACCESS_REPOS=()

# Track PR creation stats
PRS_CREATED=0
REPOS_SKIPPED=()
REPOS_NO_CHANGES=()
REPOS_WITH_ERRORS=()
REPOS_NO_MAINTAINERS=()
REPOS_FILE_EXISTS=()  # Repos where MAINTAINERS.md already exists (needs manual validation)

log_info "Starting MAINTAINERS.md file creation process"
if [ -n "$CURRENT_USER" ]; then
    log_info "Current user: $CURRENT_USER"
fi
if [ -n "$TEST_REPO" ]; then
    log_info "TEST MODE: Processing single repository: $TEST_REPO"
else
    log_info "Organizations: ${ORGS[*]}"
fi
if [ "$DRY_RUN" = true ]; then
    log_warn "DRY RUN MODE - No changes will be made"
fi

# Function to get default branch name
get_default_branch() {
    local org="$1"
    local repo="$2"
    gh api "/repos/$org/$repo" --jq '.default_branch' 2>/dev/null || echo "main"
}

# Function to check if a MAINTAINERS.md file exists in a repo (any location, any case)
# Returns: 0 if file exists, 1 if not
# Outputs: file path if found (to stdout)
file_exists_in_repo() {
    local org="$1"
    local repo="$2"
    local default_branch="$3"
    
    # Check common locations and case variations
    local locations=(
        "MAINTAINERS.md"
        "maintainers.md"
        "Maintainers.md"
        "MAINTAINERS.MD"
        "docs/MAINTAINERS.md"
        "docs/maintainers.md"
        "docs/Maintainers.md"
        ".github/MAINTAINERS.md"
        ".github/maintainers.md"
        ".github/Maintainers.md"
    )
    
    for file_path in "${locations[@]}"; do
        if gh api "/repos/$org/$repo/contents/$file_path?ref=$default_branch" &>/dev/null; then
            echo "$file_path"  # Output the path where file was found
            return 0  # File exists
        fi
    done
    
    # Also search for any file matching maintainers pattern (case-insensitive)
    # Using GitHub API search - check if any file matches
    # Note: Code search API has rate limits (30/min), so this might fail silently
    # If it fails, we'll just rely on the explicit path checks above
    local search_results=$(gh api "/search/code?q=filename:maintainers.md+repo:$org/$repo" --jq '.items[]?.path' 2>/dev/null)
    if [ -n "$search_results" ] && [ "$search_results" != "null" ]; then
        # Get the first match
        local first_match=$(echo "$search_results" | head -1)
        echo "$first_match"
        return 0  # Found a match
    fi
    
    return 1  # File doesn't exist
}

# Function to create a branch using GitHub API
create_branch_via_api() {
    local org="$1"
    local repo="$2"
    local branch_name="$3"
    local base_branch="$4"
    local base_sha="$5"
    
    # Create branch using refs API
    # Return success (0) if branch created, failure (1) otherwise
    if gh api -X POST "/repos/$org/$repo/git/refs" \
        -f ref="refs/heads/$branch_name" \
        -f sha="$base_sha" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Function to create a file using GitHub API (no cloning needed)
create_file_via_api() {
    local org="$1"
    local repo="$2"
    local branch="$3"
    local file_path="$4"
    local content="$5"
    local commit_message="$6"
    
    # Validate content is not empty
    if [ -z "$content" ]; then
        log_error "Content is empty, cannot create file"
        return 1
    fi
    
    # Base64 encode the content (handle special characters properly)
    local encoded_content=$(echo -n "$content" | base64)
    
    if [ -z "$encoded_content" ]; then
        log_error "Failed to encode content"
        return 1
    fi
    
    # Create the file using GitHub Contents API
    # Return success (0) if file created, failure (1) otherwise
    if gh api -X PUT "/repos/$org/$repo/contents/$file_path" \
        -f branch="$branch" \
        -f message="$commit_message" \
        -f content="$encoded_content" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Function to get the SHA of the default branch head
get_default_branch_sha() {
    local org="$1"
    local repo="$2"
    local default_branch="$3"
    gh api "/repos/$org/$repo/git/ref/heads/$default_branch" --jq '.object.sha' 2>/dev/null
}

# Function to create a file using GitHub API (no cloning needed)
create_file_via_api() {
    local org="$1"
    local repo="$2"
    local branch="$3"
    local file_path="$4"
    local content="$5"
    local base_sha="$6"
    local commit_message="$7"
    
    # Base64 encode the content
    local encoded_content=$(echo -n "$content" | base64)
    
    # Create the file using GitHub Contents API
    gh api -X PUT "/repos/$org/$repo/contents/$file_path" \
        -f branch="$branch" \
        -f message="$commit_message" \
        -f content="$encoded_content" \
        -f sha="$base_sha" 2>/dev/null
}

# Function to check if PR already exists
pr_exists() {
    local org="$1"
    local repo="$2"
    local branch="$3"
    
    # Check for open PRs with the same branch name
    gh pr list --repo "$org/$repo" --head "$org:$branch" --state open --json number -q '.[].number' 2>/dev/null | grep -q .
}

# Function to check if user has maintainer/admin access
check_repo_access() {
    local org="$1"
    local repo="$2"
    
    # Try to get repo info - if we can't access it, we don't have permissions
    local repo_info=$(gh api "/repos/$org/$repo" 2>/dev/null)
    if [ -z "$repo_info" ]; then
        return 1
    fi
    
    # Check if we can get the default branch (requires read access at minimum)
    local default_branch=$(echo "$repo_info" | jq -r '.default_branch' 2>/dev/null)
    if [ -z "$default_branch" ] || [ "$default_branch" = "null" ]; then
        return 1
    fi
    
    return 0
}

# Function to check if a team is a FINOS team (should be ignored)
is_finos_team() {
    local team_slug="$1"
    local org="$2"
    
    # Explicitly check for known FINOS admin/staff teams that should be ignored
    case "$team_slug" in
        finos-admins|finos-admin|finos-staff|finos-staff-team|finos-admins-team)
            return 0  # It's a FINOS team - should be ignored
            ;;
        finos-*)
            # Any team starting with finos- should be excluded
            return 0
            ;;
    esac
    
    # Check if team belongs to finos org
    # Teams in the finos org should be ignored
    local team_info=$(gh api "/orgs/finos/teams/$team_slug" 2>/dev/null)
    if [ -n "$team_info" ]; then
        # Verify it's actually a team (not an error response)
        local team_id=$(echo "$team_info" | jq -r '.id // empty' 2>/dev/null)
        if [ -n "$team_id" ] && [ "$team_id" != "null" ]; then
            return 0  # It's a FINOS team - should be ignored
        fi
    fi
    
    return 1  # Not a FINOS team
}

# Function to get user profile information
get_user_info() {
    local username="$1"
    local user_info=$(gh api "/users/$username" 2>/dev/null)
    
    if [ -z "$user_info" ]; then
        echo "$username|||"
        return
    fi
    
    local name=$(echo "$user_info" | jq -r '.name // ""')
    local email=$(echo "$user_info" | jq -r '.email // ""')
    
    # If email is not public, try to get it from their profile
    if [ -z "$email" ] || [ "$email" = "null" ]; then
        # Try to get email from their public profile events (limited)
        email=""
    fi
    
    echo "$username|$name|$email"
}

# Function to check if a username is already in the maintainers list
is_in_list() {
    local username="$1"
    local list="$2"
    echo "$list" | grep -Fxq "$username" 2>/dev/null
}

# Function to check if a user should be excluded (service accounts, etc.)
should_exclude_user() {
    local username="$1"
    
    # Exclude known service accounts, bots, and organizational accounts
    case "$username" in
        finos-admin|thelinuxfoundation|finos-bot|finos[bot]|linuxfoundation|lf-bot)
            return 0  # Should be excluded
            ;;
    esac
    
    return 1  # Should be included
}

# Wrapper for log_info that redirects to stderr (to avoid capturing log output)
log_info_stderr() {
    log_info "$1" >&2
}

# Function to get all maintainers for a repository
get_maintainers() {
    local org="$1"
    local repo="$2"
    local maintainers_list=""
    local finos_admins_members=""
    
    # Use log_info_stderr to redirect all log output to stderr
    # This prevents log messages from being captured with the maintainers list
    
    # Get members of finos-admins team to exclude them
    log_info_stderr "  Fetching finos-admins team members to exclude..."
    finos_admins_members=$(gh api "/orgs/finos/teams/finos-admins/members?per_page=100" --jq '.[].login' 2>/dev/null)
    if [ -n "$finos_admins_members" ]; then
        local admin_count=$(echo "$finos_admins_members" | grep -v '^$' | wc -l | tr -d ' ')
        log_info_stderr "    Found $admin_count finos-admins team members to exclude"
    fi
    
    # Get direct collaborators with maintainer or admin role
    log_info_stderr "  Fetching collaborators with maintainer or admin role..."
    local collaborators=$(gh api "/repos/$org/$repo/collaborators?per_page=100" --jq '.[] | select(.permissions.maintain == true or .permissions.admin == true) | .login' 2>/dev/null)
    
    if [ -n "$collaborators" ]; then
        while IFS= read -r username; do
            if [ -n "$username" ] && [ "$username" != "null" ]; then
                # Exclude service accounts and bots
                if should_exclude_user "$username"; then
                    log_info_stderr "    Excluding service account/bot: $username"
                    continue
                fi
                
                # Exclude members of finos-admins team
                if [ -n "$finos_admins_members" ] && is_in_list "$username" "$finos_admins_members"; then
                    log_info_stderr "    Excluding finos-admins team member: $username"
                    continue
                fi
                
                if ! is_in_list "$username" "$maintainers_list"; then
                    if [ -z "$maintainers_list" ]; then
                        maintainers_list="$username"
                    else
                        maintainers_list="${maintainers_list}"$'\n'"${username}"
                    fi
                    log_info_stderr "    Found maintainer (user): $username"
                fi
            fi
        done <<< "$collaborators"
    fi
    
    # Get teams with maintainer role
    log_info_stderr "  Fetching teams with maintainer role..."
    local teams_json=$(gh api "/repos/$org/$repo/teams?per_page=100" 2>/dev/null)
    
    if [ -n "$teams_json" ]; then
        # Get team slugs with maintain or admin permission
        local team_slugs=$(echo "$teams_json" | jq -r '.[] | select(.permission == "maintain" or .permission == "admin") | .slug' 2>/dev/null)
        
        if [ -n "$team_slugs" ]; then
            while IFS= read -r team_slug; do
                if [ -z "$team_slug" ] || [ "$team_slug" = "null" ]; then
                    continue
                fi
                
                # Skip FINOS teams
                if is_finos_team "$team_slug" "$org"; then
                    log_info_stderr "    Skipping FINOS team: $team_slug"
                    continue
                fi
                
                log_info_stderr "    Found maintainer team: $team_slug"
                
                # Get team members - try the repo's org first
                local team_members=$(gh api "/orgs/$org/teams/$team_slug/members?per_page=100" --jq '.[].login' 2>/dev/null)
                
                if [ -n "$team_members" ]; then
                    while IFS= read -r member; do
                        if [ -n "$member" ] && [ "$member" != "null" ]; then
                            # Exclude service accounts and bots
                            if should_exclude_user "$member"; then
                                log_info_stderr "      Excluding service account/bot: $member"
                                continue
                            fi
                            
                            # Exclude members of finos-admins team
                            if [ -n "$finos_admins_members" ] && is_in_list "$member" "$finos_admins_members"; then
                                log_info_stderr "      Excluding finos-admins team member: $member"
                                continue
                            fi
                            
                            if ! is_in_list "$member" "$maintainers_list"; then
                                if [ -z "$maintainers_list" ]; then
                                    maintainers_list="$member"
                                else
                                    maintainers_list="${maintainers_list}"$'\n'"${member}"
                                fi
                                log_info_stderr "      Team member: $member"
                            fi
                        fi
                    done <<< "$team_members"
                fi
            done <<< "$team_slugs"
        fi
    fi
    
    # Debug: log all maintainers found (redirect to stderr so it doesn't get captured)
    if [ -n "$maintainers_list" ]; then
        log_info_stderr "  Final maintainers list:"
        local count=0
        while IFS= read -r username; do
            if [ -n "$username" ]; then
                count=$((count + 1))
                log_info_stderr "    $count. $username"
            fi
        done <<< "$maintainers_list"
        log_info_stderr "  Total: $count maintainer(s)"
    fi
    
    # Return maintainers as newline-separated string (only the actual data, not logs)
    echo "$maintainers_list"
}

# Function to generate MAINTAINERS.md content
generate_maintainers_file() {
    local org="$1"
    local repo="$2"
    local maintainers_list="$3"
    
    local content="# Maintainers\n\n"
    content+="This file lists the maintainers of this repository.\n\n"
    content+="For information about maintainer responsibilities and resources, please see the [FINOS Maintainers Cheatsheet](https://community.finos.org/docs/finos-maintainers-cheatsheet).\n\n"
    
    if [ -z "$maintainers_list" ]; then
        content+="No maintainers found. Please add maintainers to this list.\n"
        echo "$content"
        return
    fi
    
    content+="| GitHub Username | Name | Email |\n"
    content+="|----------------|------|-------|\n"
    
    # Sort maintainers alphabetically
    local sorted_maintainers=$(echo "$maintainers_list" | sort)
    
    while IFS= read -r username; do
        if [ -z "$username" ]; then
            continue
        fi
        
        local user_info=$(get_user_info "$username")
        IFS='|' read -r gh_username name email <<< "$user_info"
        
        # Escape pipe characters in name/email if present
        name=$(echo "$name" | sed 's/|/\\|/g')
        email=$(echo "$email" | sed 's/|/\\|/g')
        
        # Add placeholder text if name or email is empty
        if [ -z "$name" ] || [ "$name" = "null" ]; then
            name="*please add name*"
        fi
        
        if [ -z "$email" ] || [ "$email" = "null" ]; then
            email="*please add email*"
        fi
        
        content+="| @$gh_username | $name | $email |\n"
    done <<< "$sorted_maintainers"
    
    echo "$content"
}

# Function to process a single repository
process_repo() {
    local org="$1"
    local repo="$2"
    
    log_info "Processing repository: $org/$repo"
    
    # Check if user has access to the repository
    if ! check_repo_access "$org" "$repo"; then
        log_error "⚠️  INSUFFICIENT ACCESS: $org/$repo - Cannot access repository or insufficient permissions. Skipping."
        INSUFFICIENT_ACCESS_REPOS+=("$org/$repo")
        return 1
    fi
        
    # Check if PR already exists
    if pr_exists "$org" "$repo" "$BRANCH_NAME"; then
        if [ "$SKIP_EXISTING_PR" = true ]; then
            log_warn "PR already exists for $org/$repo. Skipping."
            REPOS_SKIPPED+=("$org/$repo (PR already exists)")
            return 0
        else
            log_warn "PR already exists for $org/$repo. Continuing anyway."
        fi
    fi
    
    # Get maintainers
    log_info "  Getting maintainers for $org/$repo..."
    # Capture maintainers - log output is redirected to stderr in get_maintainers
    # So we only capture stdout which contains the maintainers list
    local maintainers=$(get_maintainers "$org" "$repo" 2>/dev/null)
    
    # Count non-empty lines
    local maintainer_count=0
    if [ -n "$maintainers" ]; then
        maintainer_count=$(echo "$maintainers" | grep -v '^$' | wc -l | tr -d ' ')
    fi
    
    if [ "$maintainer_count" -eq 0 ]; then
        log_warn "No maintainers found for $org/$repo. Skipping MAINTAINERS.md creation."
        REPOS_NO_MAINTAINERS+=("$org/$repo")
        return 0
    else
        log_info "  Found $maintainer_count maintainer(s)"
    fi
    
    # Get default branch
    default_branch=$(get_default_branch "$org" "$repo")
    log_info "Default branch: $default_branch"
    
    # Check if MAINTAINERS.md already exists using API (any location, any case)
    local existing_file_path
    existing_file_path=$(file_exists_in_repo "$org" "$repo" "$default_branch")
    if [ $? -eq 0 ] && [ -n "$existing_file_path" ]; then
        log_warn "⚠️  MAINTAINERS.md file already exists at '$existing_file_path' in $org/$repo"
        log_warn "   Skipping - content not validated. Please manually verify and update if needed."
        REPOS_FILE_EXISTS+=("$org/$repo (found at: $existing_file_path)")
        return 0
    fi
    
    # Check if branch already exists on remote
    if gh api "/repos/$org/$repo/git/ref/heads/$BRANCH_NAME" &>/dev/null; then
        # Branch exists on remote - check if PR exists
        if pr_exists "$org" "$repo" "$BRANCH_NAME"; then
            log_warn "Branch $BRANCH_NAME already exists on remote with an open PR. Skipping."
            REPOS_SKIPPED+=("$org/$repo (PR already exists)")
            return 0
        else
            log_warn "Branch $BRANCH_NAME exists on remote but no open PR found. Deleting remote branch."
            gh api -X DELETE "/repos/$org/$repo/git/refs/heads/$BRANCH_NAME" &>/dev/null || log_warn "Could not delete remote branch"
        fi
    fi
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would create MAINTAINERS.md file via API for $org/$repo"
        log_info "[DRY RUN] Would create branch $BRANCH_NAME and PR"
        return 0
    fi
    
    # Get the SHA of the default branch head
    local base_sha=$(gh api "/repos/$org/$repo/git/ref/heads/$default_branch" --jq '.object.sha' 2>/dev/null)
    if [ -z "$base_sha" ]; then
        log_error "Failed to get base SHA for $org/$repo"
        REPOS_WITH_ERRORS+=("$org/$repo (failed to get base SHA)")
        return 1
    fi
    
    # Create new branch using API
    log_info "Creating branch $BRANCH_NAME from $default_branch"
    if ! create_branch_via_api "$org" "$repo" "$BRANCH_NAME" "$default_branch" "$base_sha"; then
        log_error "Failed to create branch $BRANCH_NAME for $org/$repo"
        REPOS_WITH_ERRORS+=("$org/$repo (branch creation failed)")
        return 1
    fi
    
    # Generate MAINTAINERS.md content
    log_info "Generating MAINTAINERS.md file..."
    local maintainers_content=$(generate_maintainers_file "$org" "$repo" "$maintainers")
    
    # Validate content was generated
    if [ -z "$maintainers_content" ]; then
        log_error "Failed to generate MAINTAINERS.md content for $org/$repo"
        # Clean up the branch we created
        gh api -X DELETE "/repos/$org/$repo/git/refs/heads/$BRANCH_NAME" &>/dev/null
        REPOS_WITH_ERRORS+=("$org/$repo (content generation failed)")
        return 1
    fi
    
    # Get current user for DCO sign-off
    local current_user_name=$(gh api user --jq '.name // .login' 2>/dev/null || echo "")
    local current_user_email=$(gh api user --jq '.email // ""' 2>/dev/null || echo "")
    
    # Create commit message with DCO sign-off
    local commit_msg="Add MAINTAINERS.md file"
    if [ -n "$current_user_name" ] && [ -n "$current_user_email" ]; then
        commit_msg="$commit_msg

Signed-off-by: $current_user_name <$current_user_email>"
    fi
    
    # Create file using API (no cloning needed!)
    log_info "Creating MAINTAINERS.md file via API..."
    if ! create_file_via_api "$org" "$repo" "$BRANCH_NAME" "MAINTAINERS.md" "$maintainers_content" "$commit_msg"; then
        log_error "Failed to create MAINTAINERS.md file for $org/$repo"
        # Clean up the branch we created
        gh api -X DELETE "/repos/$org/$repo/git/refs/heads/$BRANCH_NAME" &>/dev/null
        REPOS_WITH_ERRORS+=("$org/$repo (file creation failed)")
        return 1
    fi
    
    # Create pull request
    log_info "Creating pull request for $org/$repo"
    if gh pr create \
        --repo "$org/$repo" \
        --title "$PR_TITLE" \
        --body "$PR_BODY" \
        --head "$BRANCH_NAME" \
        --base "$default_branch" &>/dev/null; then
        log_success "Created PR for $org/$repo"
        PRS_CREATED=$((PRS_CREATED + 1))
    else
        log_error "Failed to create PR for $org/$repo"
        # Clean up the branch if PR creation fails
        log_info "Cleaning up branch $BRANCH_NAME due to PR creation failure"
        gh api -X DELETE "/repos/$org/$repo/git/refs/heads/$BRANCH_NAME" &>/dev/null
        REPOS_WITH_ERRORS+=("$org/$repo (PR creation failed)")
    fi
        
    log_success "Completed processing for $org/$repo"
    echo ""
}

# Main processing logic
if [ -n "$TEST_REPO" ]; then
    # Test mode: process single repository
    if [[ ! "$TEST_REPO" =~ ^[^/]+/[^/]+$ ]]; then
        log_error "Invalid repository format: $TEST_REPO"
        log_error "Expected format: org/repo-name (e.g., finos/repo-name)"
        exit 1
    fi
    
    org="${TEST_REPO%%/*}"
    repo="${TEST_REPO#*/}"
    
    # Verify repository exists
    if ! gh api "/repos/$org/$repo" &>/dev/null; then
        log_error "Repository $org/$repo does not exist or is not accessible"
        exit 1
    fi
    
    process_repo "$org" "$repo"
else
    # Normal mode: process all repositories in organizations
    for org in "${ORGS[@]}"; do
        log_info "Processing organization: $org"
        
        # Get all repositories in the organization
        repos=$(gh repo list "$org" --limit $GITHUB_API_LIMIT --json name -q '.[].name' 2>/dev/null)
        
        if [ -z "$repos" ]; then
            log_warn "No repositories found in organization: $org"
            continue
        fi
        
        repo_count=$(echo "$repos" | wc -l | tr -d ' ')
        log_info "Found $repo_count repositories in $org"
        
        # Process each repository
        for repo in $repos; do
            process_repo "$org" "$repo"
        done
    done
fi

log_success "MAINTAINERS.md file creation process completed!"

# Print summary
echo ""
log_info "=========================================="
log_info "SUMMARY"
log_info "=========================================="
log_success "PRs Created: $PRS_CREATED"

# Report repos with insufficient access
if [ ${#INSUFFICIENT_ACCESS_REPOS[@]} -gt 0 ]; then
    echo ""
    log_warn "Repositories with insufficient access (${#INSUFFICIENT_ACCESS_REPOS[@]} total):"
    for repo in "${INSUFFICIENT_ACCESS_REPOS[@]}"; do
        echo "  - $repo"
    done
fi

# Report repos that were skipped
if [ ${#REPOS_SKIPPED[@]} -gt 0 ]; then
    echo ""
    log_warn "Repositories skipped (${#REPOS_SKIPPED[@]} total):"
    for repo in "${REPOS_SKIPPED[@]}"; do
        echo "  - $repo"
    done
fi

# Report repos where MAINTAINERS.md already exists (needs manual validation)
if [ ${#REPOS_FILE_EXISTS[@]} -gt 0 ]; then
    echo ""
    log_warn "⚠️  Repositories with existing MAINTAINERS.md file (${#REPOS_FILE_EXISTS[@]} total):"
    log_warn "   These files were not validated - please manually check and update if needed:"
    for repo_info in "${REPOS_FILE_EXISTS[@]}"; do
        echo "  - $repo_info"
    done
fi

# Report repos with no maintainers
if [ ${#REPOS_NO_MAINTAINERS[@]} -gt 0 ]; then
    echo ""
    log_warn "Repositories with no maintainers (${#REPOS_NO_MAINTAINERS[@]} total):"
    for repo in "${REPOS_NO_MAINTAINERS[@]}"; do
        echo "  - $repo"
    done
fi

# Report repos with no changes needed
if [ ${#REPOS_NO_CHANGES[@]} -gt 0 ]; then
    echo ""
    log_info "Repositories with no changes needed (${#REPOS_NO_CHANGES[@]} total):"
    for repo in "${REPOS_NO_CHANGES[@]}"; do
        echo "  - $repo"
    done
fi

# Report repos with errors
if [ ${#REPOS_WITH_ERRORS[@]} -gt 0 ]; then
    echo ""
    log_error "Repositories with errors (${#REPOS_WITH_ERRORS[@]} total):"
    for repo in "${REPOS_WITH_ERRORS[@]}"; do
        echo "  - $repo"
    done
fi

echo ""
log_info "=========================================="
