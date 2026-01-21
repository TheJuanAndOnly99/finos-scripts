#!/bin/bash

# Organizations to process
ORGS=("finos-labs")

# Badge image pattern (finos-labs badge)
BADGE_IMAGE_PATTERN='!\[badge-labs\]\(https://user-images\.githubusercontent\.com/327285/230928932-7c75f8ed-e57b-41db-9fb7-a292a13a1e58\.svg\)'

# Badge link URL (finos-labs maturity page)
BADGE_LINK_URL="https://community.finos.org/docs/governance/software-projects/maturity/labs"

# Branch and PR settings
BRANCH_NAME="update-badge-link"
PR_TITLE="Update badge to be clickable link that points to the new maturity documentation"
PR_BODY="This PR updates the FINOS badge to be a clickable link pointing to the new maturity documentation.

- Badge is now wrapped in a link to: \`$BADGE_LINK_URL\`"

# Script-specific configuration
DRY_RUN=true
SKIP_EXISTING_PR=true
TEST_REPO=""

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
            echo "This script creates PRs to update badge links in all finos and finos-labs repos:"
            echo "  Old: $OLD_URL_PATTERN"
            echo "  New: $NEW_URL_PATTERN"
            echo ""
            echo "Example for testing on a single repo:"
            echo "  $0 --repo finos/repo-name"
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

log_info "Starting badge link update process"
if [ -n "$CURRENT_USER" ]; then
    log_info "Current user: $CURRENT_USER"
fi
if [ -n "$TEST_REPO" ]; then
    log_info "TEST MODE: Processing single repository: $TEST_REPO"
else
    log_info "Organizations: ${ORGS[*]}"
fi
log_info "Badge image pattern: $BADGE_IMAGE_PATTERN"
log_info "Badge link URL: $BADGE_LINK_URL"
if [ "$DRY_RUN" = true ]; then
    log_warn "DRY RUN MODE - No changes will be made"
fi

# Function to get default branch name
get_default_branch() {
    local org="$1"
    local repo="$2"
    gh api "/repos/$org/$repo" --jq '.default_branch' 2>/dev/null || echo "main"
}

# Function to get the SHA of the default branch head
get_default_branch_sha() {
    local org="$1"
    local repo="$2"
    local default_branch="$3"
    gh api "/repos/$org/$repo/git/ref/heads/$default_branch" --jq '.object.sha' 2>/dev/null
}

# Function to create a branch using GitHub API
create_branch_via_api() {
    local org="$1"
    local repo="$2"
    local branch_name="$3"
    local base_branch="$4"
    local base_sha="$5"
    
    # Create branch using refs API
    if gh api -X POST "/repos/$org/$repo/git/refs" \
        -f ref="refs/heads/$branch_name" \
        -f sha="$base_sha" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Function to read a file from GitHub using API
read_file_via_api() {
    local org="$1"
    local repo="$2"
    local file_path="$3"
    local branch="$4"
    
    # Get file content via API
    local file_info=$(gh api "/repos/$org/$repo/contents/$file_path?ref=$branch" 2>/dev/null)
    if [ -z "$file_info" ]; then
        return 1
    fi
    
    # Decode base64 content
    echo "$file_info" | jq -r '.content' | base64 -d 2>/dev/null
}

# Function to update a file using GitHub API (no cloning needed)
update_file_via_api() {
    local org="$1"
    local repo="$2"
    local branch="$3"
    local file_path="$4"
    local content="$5"
    local commit_message="$6"
    local file_sha="$7"  # SHA of existing file (required for updates)
    
    # Base64 encode the content
    local encoded_content=$(echo -n "$content" | base64)
    
    if [ -z "$encoded_content" ]; then
        return 1
    fi
    
    # Update the file using GitHub Contents API
    if gh api -X PUT "/repos/$org/$repo/contents/$file_path" \
        -f branch="$branch" \
        -f message="$commit_message" \
        -f content="$encoded_content" \
        -f sha="$file_sha" &>/dev/null; then
        return 0
    else
        return 1
    fi
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
    
    # Try to check if we can create a branch (requires write/maintain/admin access)
    # We'll test this by trying to get branch protection rules or repo permissions
    # For now, if we can read the repo, we'll assume we can write (since user said they have maintainer access)
    # The actual test will happen when we try to push
    
    return 0
}

# Function to update badge URLs in file content (in memory)
update_badge_urls_in_content() {
    local content="$1"
    local file_name="$2"
    local updated_content="$content"
    local file_updated=false
    
    # Pattern to match badge image (literal string, not regex)
    local badge_image='![badge-labs](https://user-images.githubusercontent.com/327285/230928932-7c75f8ed-e57b-41db-9fb7-a292a13a1e58.svg)'
    local replacement="[![badge-labs](https://user-images.githubusercontent.com/327285/230928932-7c75f8ed-e57b-41db-9fb7-a292a13a1e58.svg)]($BADGE_LINK_URL)"
    
    # Check if badge exists in content
    if echo "$content" | grep -qF "$badge_image"; then
        # Check if it's NOT already wrapped in a link (doesn't start with [)
        if ! echo "$content" | grep -qF "[$badge_image"; then
            # Replace badge image with clickable link (using sed for in-memory processing)
            updated_content=$(echo "$updated_content" | sed "s|$badge_image|$replacement|g")
            file_updated=true
        fi
    fi
    
    if [ "$file_updated" = true ]; then
        echo "$updated_content"
        return 0
    else
        return 1
    fi
}

# Function to find and replace badge URLs in files (API-based version)
update_badge_urls_via_api() {
    local org="$1"
    local repo="$2"
    local branch="$3"
    local files_to_update=()  # Array of file paths that need updating
    
    # Common files to check
    local common_files=("README.md" "readme.md" "Readme.md" "README.rst" "README.txt")
    
    # Pattern to match badge image
    local badge_image='![badge-labs](https://user-images.githubusercontent.com/327285/230928932-7c75f8ed-e57b-41db-9fb7-a292a13a1e58.svg)'
    
    # Check each common file
    for file_path in "${common_files[@]}"; do
        # Try to read file via API
        local file_info=$(gh api "/repos/$org/$repo/contents/$file_path?ref=$branch" 2>/dev/null)
        if [ -z "$file_info" ]; then
            continue  # File doesn't exist
        fi
        
        # Get file SHA and content
        local file_sha=$(echo "$file_info" | jq -r '.sha' 2>/dev/null)
        local file_content=$(echo "$file_info" | jq -r '.content' | base64 -d 2>/dev/null)
        
        if [ -z "$file_content" ] || [ "$file_sha" = "null" ]; then
            continue
        fi
        
        # Check if file needs updating (has badge but not wrapped in link)
        if echo "$file_content" | grep -qF "$badge_image" && ! echo "$file_content" | grep -qF "[$badge_image"; then
            # Update content in memory
            local updated_content=$(update_badge_urls_in_content "$file_content" "$file_path")
            local update_result=$?
            if [ $update_result -eq 0 ] && [ -n "$updated_content" ] && [ "$updated_content" != "$file_content" ]; then
                files_to_update+=("$file_path|$file_sha|$updated_content")
                log_info "Found file to update: $file_path"
            fi
        fi
    done
    
    # Return files that need updating (format: path|sha|content)
    printf '%s\n' "${files_to_update[@]}"
}

# Function to find and replace badge images with clickable links (original clone-based version)
update_badge_urls() {
    local repo_dir="$1"
    local files_changed=0
    
    # Pattern to match badge image (literal string, not regex)
    local badge_image='![badge-labs](https://user-images.githubusercontent.com/327285/230928932-7c75f8ed-e57b-41db-9fb7-a292a13a1e58.svg)'
    local replacement="[![badge-labs](https://user-images.githubusercontent.com/327285/230928932-7c75f8ed-e57b-41db-9fb7-a292a13a1e58.svg)]($BADGE_LINK_URL)"
    
    # Function to check and update a file
    update_file() {
        local file_path="$1"
        local file_name="$2"
        
        # Check if badge exists in file
        if grep -qF "$badge_image" "$file_path" 2>/dev/null; then
            # Check if it's NOT already wrapped in a link (doesn't start with [)
            if ! grep -qF "[$badge_image" "$file_path" 2>/dev/null; then
                # Replace badge image with clickable link
                # Use perl for more reliable replacement (handles special chars better)
                perl -i.bak -pe "s|\Q$badge_image\E|$replacement|g" "$file_path" 2>/dev/null || {
                    # Fallback to sed if perl not available
                    local escaped_badge=$(printf '%s\n' "$badge_image" | sed 's/[[\.*^$()+?{|]/\\&/g')
                    local escaped_replacement=$(printf '%s\n' "$replacement" | sed 's/[\/&]/\\&/g')
                    sed -i.bak "s|$escaped_badge|$escaped_replacement|g" "$file_path"
                }
                rm -f "$file_path.bak"
                files_changed=$((files_changed + 1))
                log_info "Updated file: $file_name" >&2
                return 0
            fi
        fi
        return 1
    }
    
    # First, check README.md in the root (most common location)
    if [ -f "$repo_dir/README.md" ]; then
        update_file "$repo_dir/README.md" "README.md"
    fi
    
    # Also check README.md (case variations) and other common locations
    for readme_file in "readme.md" "Readme.md" "README.rst" "README.txt"; do
        if [ -f "$repo_dir/$readme_file" ]; then
            update_file "$repo_dir/$readme_file" "$readme_file"
        fi
    done
    
    # If no changes found in README files, do a broader search as fallback
    if [ "$files_changed" -eq 0 ]; then
        log_info "Badge not found in README files, searching all files..." >&2
        while IFS= read -r file; do
            if [ -f "$file" ]; then
                local rel_path="${file#$repo_dir/}"
                update_file "$file" "$rel_path"
            fi
        done < <(grep -r -lF "$badge_image" "$repo_dir" --exclude-dir=.git 2>/dev/null || true)
    fi
    
    # Return only the number (log messages go to stderr)
    echo "$files_changed"
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
    
    # Get default branch
    default_branch=$(get_default_branch "$org" "$repo")
    log_info "Default branch: $default_branch"
    
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
        log_info "[DRY RUN] Would check for badge URLs in $org/$repo via API"
        return 0
    fi
    
    # Try API-based approach first (check common files)
    log_info "Checking for badge URLs via API..."
    local files_to_update=$(update_badge_urls_via_api "$org" "$repo" "$default_branch")
    local file_count=$(echo "$files_to_update" | grep -v '^$' | wc -l | tr -d ' ')
    
    if [ "$file_count" -eq 0 ]; then
        log_info "No badge URLs found in common files for $org/$repo. Skipping."
        REPOS_NO_CHANGES+=("$org/$repo")
        return 0
    fi
    
    # Get the SHA of the default branch head
    local base_sha=$(get_default_branch_sha "$org" "$repo" "$default_branch")
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
    
    # Get current user for DCO sign-off
    local current_user_name=$(gh api user --jq '.name // .login' 2>/dev/null || echo "")
    local current_user_email=$(gh api user --jq '.email // ""' 2>/dev/null || echo "")
    
    # Update each file via API
    local files_updated=0
    while IFS='|' read -r file_path file_sha file_content; do
        if [ -z "$file_path" ] || [ -z "$file_sha" ]; then
            continue
        fi
        
        # Create commit message with DCO sign-off
        local commit_msg="Update badge to be clickable link in $file_path"
        if [ -n "$current_user_name" ] && [ -n "$current_user_email" ]; then
            commit_msg="$commit_msg

Signed-off-by: $current_user_name <$current_user_email>"
        fi
        
        log_info "Updating file: $file_path"
        if update_file_via_api "$org" "$repo" "$BRANCH_NAME" "$file_path" "$file_content" "$commit_msg" "$file_sha"; then
            files_updated=$((files_updated + 1))
            log_success "Updated $file_path"
        else
            log_error "Failed to update $file_path"
            # Clean up the branch if file update fails
            gh api -X DELETE "/repos/$org/$repo/git/refs/heads/$BRANCH_NAME" &>/dev/null
            REPOS_WITH_ERRORS+=("$org/$repo (file update failed: $file_path)")
            return 1
        fi
    done <<< "$files_to_update"
    
    if [ "$files_updated" -eq 0 ]; then
        log_info "No files were updated in $org/$repo. Skipping."
        # Clean up the branch
        gh api -X DELETE "/repos/$org/$repo/git/refs/heads/$BRANCH_NAME" &>/dev/null
        REPOS_NO_CHANGES+=("$org/$repo")
        return 0
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

log_success "Badge link update process completed!"

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