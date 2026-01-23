#!/bin/bash

# This script is used to update badges in FINOS organizations
# Supports both 'finos' and 'finos-labs' organizations with org-specific configurations

# =============================================================================
# ORG-SPECIFIC CONFIGURATIONS
# =============================================================================

# Configuration for 'finos' organization
configure_finos() {
    # Badge URL replacement (for finos org badges)
    BASE_URL="https://community.finos.org/docs/governance/Software-Projects"
    OLD_BASE_PATTERN_LOWER="https://community.finos.org/docs/governance/software-projects/stages/"
    OLD_BASE_PATTERN_UPPER="https://community.finos.org/docs/governance/Software-Projects/stages/"
    NEW_BASE_PATTERN="$BASE_URL/project-lifecycle#"
    
    # Stage mappings: old-stage -> new-stage
    STAGE_OLD=("incubating" "graduated" "archived" "active")
    STAGE_NEW=("incubating" "graduated" "archived" "graduated")
    
    # Branch and PR settings
    BRANCH_NAME="update-badge-maturity-link"
    PR_TITLE="Update badge link to point to the new maturity documentation"
    PR_BODY="This PR updates the badge link from \`/stages/\` to \`/project-lifecycle#\` to reflect the new FINOS documentation structure.

- Old format: \`https://community.finos.org/docs/governance/software-projects/stages/{stage}/\`
- New format: \`https://community.finos.org/docs/governance/Software-Projects/project-lifecycle#{stage}\`
- Note: \`active\` stage has been changed to \`graduated\`

> [!IMPORTANT]
> Please review this PR manually, ensure that there are no other occurrences of the badge logic in other files and merge at your earliest convenience, preferably within the next 2 weeks. Email help@finos.org with any questions or concerns."
}

# Configuration for 'finos-labs' organization
configure_finos_labs() {
    # Badge image pattern (finos-labs badge)
    BADGE_IMAGE='![badge-labs](https://user-images.githubusercontent.com/327285/230928932-7c75f8ed-e57b-41db-9fb7-a292a13a1e58.svg)'
    BADGE_LINK_URL="https://community.finos.org/docs/governance/software-projects/project-lifecycle/#labs"
    
    # Branch and PR settings
    BRANCH_NAME="update-badge-link"
    PR_TITLE="Update badge to be clickable link that points to the new maturity documentation"
    PR_BODY="This PR updates the FINOS badge to be a clickable link pointing to the new maturity documentation.

- Badge is now wrapped in a link to: \`$BADGE_LINK_URL\`

> [!IMPORTANT]
> Please review this PR manually, ensure that there are no other occurrences of the badge logic in other files and merge at your earliest convenience, preferably within the next 2 weeks. Email help@finos.org with any questions or concerns."
}

# =============================================================================
# SCRIPT CONFIGURATION
# =============================================================================

# Organization to process (set via --org or extracted from --repo)
SELECTED_ORG="finos-labs" # finos-labs or finos
ORGS=()  # Populated from SELECTED_ORG, used for main processing loop

# Script-specific configuration
DRY_RUN=true
SKIP_EXISTING_PR=true
TEST_REPO="finos-labs/project-blueprint"

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
        --org)
            SELECTED_ORG="$2"
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
            echo "  --org ORG                  Specify organization: 'finos' or 'finos-labs' (required if not using --repo)"
            echo "  --no-skip-existing-pr      Don't skip repos that already have an open PR"
            echo "  -h, --help                 Show this help message"
            echo ""
            echo "This script updates badges in FINOS organizations:"
            echo "  - finos: Updates badge URLs from /stages/ to /project-lifecycle#"
            echo "  - finos-labs: Makes badges clickable links"
            echo ""
            echo "Example for testing on a single repo:"
            echo "  $0 --repo finos/repo-name"
            echo ""
            echo "Example for processing an organization:"
            echo "  $0 --org finos"
            echo "  $0 --org finos-labs"
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

# Determine organization configuration
if [ -n "$TEST_REPO" ]; then
    # Extract org from test repo
    SELECTED_ORG="${TEST_REPO%%/*}"
fi

if [ -z "$SELECTED_ORG" ]; then
    log_error "Organization not specified. Use --org to specify 'finos' or 'finos-labs', or use --repo to test on a single repository."
    exit 1
fi

# Configure based on selected organization
case "$SELECTED_ORG" in
    finos)
        configure_finos
        ORGS=("finos")
        ;;
    finos-labs)
        configure_finos_labs
        ORGS=("finos-labs")
        ;;
    *)
        log_error "Unsupported organization: $SELECTED_ORG"
        log_error "Supported organizations: finos, finos-labs"
        exit 1
        ;;
esac

# Get current user
CURRENT_USER=$(gh api user --jq '.login' 2>/dev/null || echo "")

# Track repos with insufficient access
INSUFFICIENT_ACCESS_REPOS=()

# Track PR creation stats
PRS_CREATED=0
REPOS_WITH_CHANGES=()
REPOS_SKIPPED=()
REPOS_NO_CHANGES=()
REPOS_WITHOUT_BADGE=()
REPOS_WITH_ERRORS=()

log_info "Starting badge link update process"
log_info "Organization: $SELECTED_ORG"
if [ -n "$CURRENT_USER" ]; then
    log_info "Current user: $CURRENT_USER"
fi
if [ -n "$TEST_REPO" ]; then
    log_info "TEST MODE: Processing single repository: $TEST_REPO"
else
    log_info "Organizations: ${ORGS[*]}"
fi
if [ "$SELECTED_ORG" = "finos" ]; then
    log_info "Old URL base (lowercase): $OLD_BASE_PATTERN_LOWER"
    log_info "Old URL base (uppercase): $OLD_BASE_PATTERN_UPPER"
    log_info "New URL base: $NEW_BASE_PATTERN"
    log_info "Stage mappings: ${STAGE_OLD[*]} → ${STAGE_NEW[*]}"
elif [ "$SELECTED_ORG" = "finos-labs" ]; then
    log_info "Badge image: $BADGE_IMAGE"
    log_info "Badge link URL: $BADGE_LINK_URL"
fi
if [ "$DRY_RUN" = true ]; then
    log_warn "DRY RUN MODE - No changes will be made"
fi

# =============================================================================
# API ERROR HANDLING HELPERS
# =============================================================================

# Function to check if API error is a rate limit error
is_rate_limit_error() {
    local error_output="$1"
    echo "$error_output" | grep -qi "rate limit\|429\|x-ratelimit"
}

# Function to check if API error is a not found error
is_not_found_error() {
    local error_output="$1"
    echo "$error_output" | grep -qi "not found\|404"
}

# Function to check if API error is an authentication error
is_auth_error() {
    local error_output="$1"
    echo "$error_output" | grep -qi "unauthorized\|401\|forbidden\|403\|bad credentials"
}

# Function to execute API call with error handling
# Returns: 0 on success, 1 on failure
# Sets: API_ERROR_MSG with error details
api_call_with_error_handling() {
    local api_endpoint="$1"
    local org="$2"
    local repo="$3"
    local operation="$4"
    shift 4
    local api_args=("$@")
    
    # Capture both stdout and stderr
    local api_output
    local api_error
    local exit_code
    
    # Execute API call and capture output
    api_output=$(gh api "$api_endpoint" "${api_args[@]}" 2>&1)
    exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        # Success - output the result
        echo "$api_output"
        return 0
    else
        # Failure - analyze error type
        api_error="$api_output"
        
        if is_rate_limit_error "$api_error"; then
            log_error "⚠️  RATE LIMIT ERROR for $org/$repo during $operation"
            log_error "   Error details: $(echo "$api_error" | head -3)"
            log_warn "   Consider waiting before retrying or using --repo to process fewer repos"
            API_ERROR_MSG="Rate limit exceeded"
        elif is_auth_error "$api_error"; then
            log_error "⚠️  AUTHENTICATION ERROR for $org/$repo during $operation"
            log_error "   Error details: $(echo "$api_error" | head -3)"
            API_ERROR_MSG="Authentication failed"
        elif is_not_found_error "$api_error"; then
            API_ERROR_MSG="Not found"
            return 1
        else
            log_error "⚠️  API ERROR for $org/$repo during $operation"
            log_error "   Error details: $(echo "$api_error" | head -5)"
            API_ERROR_MSG="API call failed: $(echo "$api_error" | head -1)"
        fi
        return 1
    fi
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Function to get default branch name
get_default_branch() {
    local org="$1"
    local repo="$2"
    local result
    local api_error_msg
    
    result=$(api_call_with_error_handling "/repos/$org/$repo" "$org" "$repo" "get default branch" --jq '.default_branch' 2>&1)
    local exit_code=$?
    
    if [ $exit_code -eq 0 ] && [ -n "$result" ] && [ "$result" != "null" ]; then
        echo "$result"
        return 0
    else
        # On error, default to "main" but log the issue
        if [ $exit_code -ne 0 ]; then
            log_warn "Could not determine default branch for $org/$repo, defaulting to 'main'"
        fi
        echo "main"
        return 0
    fi
}

# Function to get the SHA of the default branch head
get_default_branch_sha() {
    local org="$1"
    local repo="$2"
    local default_branch="$3"
    local result
    
    result=$(api_call_with_error_handling "/repos/$org/$repo/git/ref/heads/$default_branch" "$org" "$repo" "get branch SHA" --jq '.object.sha' 2>&1)
    local exit_code=$?
    
    if [ $exit_code -eq 0 ] && [ -n "$result" ] && [ "$result" != "null" ]; then
        echo "$result"
        return 0
    else
        # Return empty string on error (caller will handle it)
        return 1
    fi
}

# Function to create a branch using GitHub API
create_branch_via_api() {
    local org="$1"
    local repo="$2"
    local branch_name="$3"
    local base_branch="$4"
    local base_sha="$5"
    
    # Create branch using refs API
    local result
    result=$(api_call_with_error_handling "/repos/$org/$repo/git/refs" "$org" "$repo" "create branch $branch_name" -X POST -f ref="refs/heads/$branch_name" -f sha="$base_sha" 2>&1)
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        return 0
    else
        # Error already logged by api_call_with_error_handling
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
    local file_info
    file_info=$(api_call_with_error_handling "/repos/$org/$repo/contents/$file_path?ref=$branch" "$org" "$repo" "read file $file_path" 2>&1)
    local exit_code=$?
    
    if [ $exit_code -ne 0 ] || [ -z "$file_info" ]; then
        return 1
    fi
    
    # Decode base64 content
    echo "$file_info" | jq -r '.content' 2>/dev/null | base64 -d 2>/dev/null
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
        log_error "Failed to encode content for $file_path in $org/$repo"
        return 1
    fi
    
    # Update the file using GitHub Contents API
    local result
    result=$(api_call_with_error_handling "/repos/$org/$repo/contents/$file_path" "$org" "$repo" "update file $file_path" -X PUT -f branch="$branch" -f message="$commit_message" -f content="$encoded_content" -f sha="$file_sha" 2>&1)
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        return 0
    else
        # Error already logged by api_call_with_error_handling
        return 1
    fi
}

# Function to check if PR already exists
pr_exists() {
    local org="$1"
    local repo="$2"
    local branch="$3"
    local result
    
    # Check for open PRs with the same branch name
    result=$(gh pr list --repo "$org/$repo" --head "$org:$branch" --state open --json number -q '.[].number' 2>&1)
    local exit_code=$?
    
    if [ $exit_code -eq 0 ] && echo "$result" | grep -q .; then
        return 0
    else
        # If it's a real error (not just "no PRs found"), log it
        if [ $exit_code -ne 0 ] && echo "$result" | grep -qiE "(error|rate limit|unauthorized|forbidden)"; then
            log_warn "Error checking for existing PR in $org/$repo: $(echo "$result" | head -1)"
        fi
        return 1
    fi
}

# Function to check if user has maintainer/admin access
check_repo_access() {
    local org="$1"
    local repo="$2"
    
    # Try to get repo info - if we can't access it, we don't have permissions
    local repo_info
    repo_info=$(api_call_with_error_handling "/repos/$org/$repo" "$org" "$repo" "check repo access" 2>&1)
    local exit_code=$?
    
    if [ $exit_code -ne 0 ] || [ -z "$repo_info" ]; then
        # Error already logged by api_call_with_error_handling
        return 1
    fi
    
    # Check if we can get the default branch (requires read access at minimum)
    local default_branch=$(echo "$repo_info" | jq -r '.default_branch' 2>/dev/null)
    if [ -z "$default_branch" ] || [ "$default_branch" = "null" ]; then
        log_warn "Could not determine default branch for $org/$repo (may indicate insufficient access)"
        return 1
    fi
    
    return 0
}

# Function to test write permissions by creating and deleting a test branch
# This verifies we can actually push/create branches (not just read)
# Critical for DRY_RUN validation - tests actual push capability
test_write_permissions() {
    local org="$1"
    local repo="$2"
    local base_branch="$3"
    local base_sha="$4"
    local test_branch_name=".test-write-permissions-$(date +%s)"
    
    # Try to create a test branch
    local create_result
    create_result=$(api_call_with_error_handling "/repos/$org/$repo/git/refs" "$org" "$repo" "test write permissions" -X POST -f ref="refs/heads/$test_branch_name" -f sha="$base_sha" 2>&1)
    local create_exit=$?
    
    if [ $create_exit -ne 0 ]; then
        return 1  # Failed to create branch - no write permissions
    fi
    
    # Immediately delete the test branch to clean up
    api_call_with_error_handling "/repos/$org/$repo/git/refs/heads/$test_branch_name" "$org" "$repo" "cleanup test branch" -X DELETE &>/dev/null
    
    return 0  # Successfully created and deleted - we have write permissions
}

# =============================================================================
# ORG-SPECIFIC BADGE TRANSFORMATION FUNCTIONS
# =============================================================================

# Function to update badge URLs in file content for 'finos' org
update_badge_urls_in_content_finos() {
    local content="$1"
    local file_name="$2"
    local updated_content="$content"
    local file_updated=false
    
    # Special case: Handle active badge image and text replacement
    if echo "$content" | grep -qF "badge-active.svg"; then
        # Replace using sed (works in memory)
        updated_content=$(echo "$updated_content" | sed -e 's|badge-active\.svg|badge-graduated.svg|g' -e 's|FINOS - Active|FINOS - Graduated|g' -e 's|/stages/active|/project-lifecycle#graduated|g')
        file_updated=true
    fi
    
    # Check if old URL pattern exists (handle both case variations)
    if echo "$updated_content" | grep -qiF "software-projects/stages/"; then
        # Process each stage mapping
        local i=0
        while [ $i -lt ${#STAGE_OLD[@]} ]; do
            local old_stage="${STAGE_OLD[$i]}"
            local new_stage="${STAGE_NEW[$i]}"
            
            # Skip active stage since we handled it above
            if [ "$old_stage" = "active" ]; then
                i=$((i + 1))
                continue
            fi
            
            # Check if this specific stage URL exists
            if echo "$updated_content" | grep -qiF "/stages/${old_stage}"; then
                local old_url_lower="${OLD_BASE_PATTERN_LOWER}${old_stage}"
                local old_url_upper="${OLD_BASE_PATTERN_UPPER}${old_stage}"
                local new_url="${NEW_BASE_PATTERN}${new_stage}"
                
                # Replace both case variations (case-insensitive)
                updated_content=$(echo "$updated_content" | sed -e "s|$old_url_lower|$new_url|gI" -e "s|$old_url_upper|$new_url|gI")
                file_updated=true
            fi
            i=$((i + 1))
        done
    fi
    
    if [ "$file_updated" = true ]; then
        echo "$updated_content"
        return 0
    else
        return 1
    fi
}

# Function to update badge URLs in file content for 'finos-labs' org
update_badge_urls_in_content_finos_labs() {
    local content="$1"
    local file_name="$2"
    local updated_content="$content"
    local file_updated=false
    
    # Pattern to match badge image (literal string, not regex)
    local replacement="[![badge-labs](https://user-images.githubusercontent.com/327285/230928932-7c75f8ed-e57b-41db-9fb7-a292a13a1e58.svg)]($BADGE_LINK_URL)"
    
    # Check if badge exists in content
    if echo "$content" | grep -qF "$BADGE_IMAGE"; then
        # Check if it's NOT already wrapped in a link (doesn't start with [)
        if ! echo "$content" | grep -qF "[$BADGE_IMAGE"; then
            # Replace badge image with clickable link (using sed for in-memory processing)
            updated_content=$(echo "$updated_content" | sed "s|$BADGE_IMAGE|$replacement|g")
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

# Unified function to update badge URLs (routes to org-specific handler)
update_badge_urls_in_content() {
    local content="$1"
    local file_name="$2"
    
    if [ "$SELECTED_ORG" = "finos" ]; then
        update_badge_urls_in_content_finos "$content" "$file_name"
    elif [ "$SELECTED_ORG" = "finos-labs" ]; then
        update_badge_urls_in_content_finos_labs "$content" "$file_name"
    else
        log_error "Unknown organization: $SELECTED_ORG"
        return 1
    fi
}

# Function to find and replace badge URLs in files (API-based version)
# Also tracks whether a badge was found (sets BADGE_FOUND variable)
update_badge_urls_via_api() {
    local org="$1"
    local repo="$2"
    local branch="$3"
    local files_to_update=()  # Array of file paths that need updating
    BADGE_FOUND=false  # Global variable to track if badge exists
    
    # Common files to check
    local common_files=("README.md" "readme.md" "Readme.md" "README.rst" "README.txt")
    
    # Check each common file
    for file_path in "${common_files[@]}"; do
        # Try to read file via API
        local file_info
        file_info=$(api_call_with_error_handling "/repos/$org/$repo/contents/$file_path?ref=$branch" "$org" "$repo" "read file $file_path" 2>&1)
        local exit_code=$?
        
        if [ $exit_code -ne 0 ] || [ -z "$file_info" ]; then
            # File doesn't exist or API error (already logged if it's a real error)
            continue
        fi
        
        # Get file SHA and content
        local file_sha=$(echo "$file_info" | jq -r '.sha' 2>/dev/null)
        local file_content=$(echo "$file_info" | jq -r '.content' 2>/dev/null | base64 -d 2>/dev/null)
        
        if [ -z "$file_content" ] || [ "$file_sha" = "null" ] || [ -z "$file_sha" ]; then
            continue
        fi
        
        # Check if badge exists (for tracking purposes)
        if [ "$SELECTED_ORG" = "finos" ]; then
            # Check for finos badge patterns
            if echo "$file_content" | grep -qiE "(badge-(incubating|graduated|archived|active)|software-projects/stages/|project-lifecycle#)"; then
                BADGE_FOUND=true
            fi
        elif [ "$SELECTED_ORG" = "finos-labs" ]; then
            # Check for finos-labs badge pattern (check for badge image URL)
            if echo "$file_content" | grep -qF "230928932-7c75f8ed-e57b-41db-9fb7-a292a13a1e58.svg"; then
                BADGE_FOUND=true
            fi
        fi
        
        # Check if file needs updating (org-specific checks)
        local needs_update=false
        if [ "$SELECTED_ORG" = "finos" ]; then
            # Check for old URL pattern or active badge
            if echo "$file_content" | grep -qiF "software-projects/stages/" || echo "$file_content" | grep -qF "badge-active.svg"; then
                needs_update=true
            fi
        elif [ "$SELECTED_ORG" = "finos-labs" ]; then
            # Check if badge exists but not wrapped in link
            if echo "$file_content" | grep -qF "$BADGE_IMAGE" && ! echo "$file_content" | grep -qF "[$BADGE_IMAGE"; then
                needs_update=true
            fi
        fi
        
        if [ "$needs_update" = true ]; then
            # Update content in memory
            local updated_content=$(update_badge_urls_in_content "$file_content" "$file_path")
            local update_exit_code=$?
            if [ $update_exit_code -eq 0 ] && [ -n "$updated_content" ] && [ "$updated_content" != "$file_content" ]; then
                files_to_update+=("$file_path|$file_sha|$updated_content")
                log_info "Found file to update: $file_path"
            fi
        fi
    done
    
    # Output badge status first (for parent shell to capture), then files
    echo "BADGE_FOUND:$BADGE_FOUND"
    # Return files that need updating (format: path|sha|content)
    printf '%s\n' "${files_to_update[@]}"
}

# =============================================================================
# MAIN PROCESSING FUNCTION
# =============================================================================

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
    local branch_check_result
    branch_check_result=$(api_call_with_error_handling "/repos/$org/$repo/git/ref/heads/$BRANCH_NAME" "$org" "$repo" "check branch existence" 2>&1)
    local branch_check_exit=$?
    
    if [ $branch_check_exit -eq 0 ] && [ -n "$branch_check_result" ]; then
        # Branch exists on remote - check if PR exists
        if pr_exists "$org" "$repo" "$BRANCH_NAME"; then
            log_warn "Branch $BRANCH_NAME already exists on remote with an open PR. Skipping."
            REPOS_SKIPPED+=("$org/$repo (PR already exists)")
            return 0
        else
            log_warn "Branch $BRANCH_NAME exists on remote but no open PR found. Deleting remote branch."
            local delete_result
            delete_result=$(api_call_with_error_handling "/repos/$org/$repo/git/refs/heads/$BRANCH_NAME" "$org" "$repo" "delete branch $BRANCH_NAME" -X DELETE 2>&1)
            if [ $? -eq 0 ]; then
                log_info "Successfully deleted branch $BRANCH_NAME"
            else
                log_warn "Could not delete remote branch $BRANCH_NAME (may have been deleted already or insufficient permissions)"
            fi
        fi
    elif [ $branch_check_exit -ne 0 ] && ! is_not_found_error "$branch_check_result"; then
        # Real API error (not just "branch doesn't exist")
        log_warn "Error checking branch existence for $org/$repo: $(echo "$branch_check_result" | head -1)"
    fi
    
    # Try API-based approach first (check common files)
    log_info "Checking for badge URLs via API..."
    local update_output=$(update_badge_urls_via_api "$org" "$repo" "$default_branch")
    # Parse badge status from first line
    local badge_status=$(echo "$update_output" | head -1 | sed 's/^BADGE_FOUND://')
    # Get files to update (skip first line)
    local files_to_update=$(echo "$update_output" | tail -n +2)
    local file_count=$(echo "$files_to_update" | grep -v '^$' | wc -l | tr -d ' ')
    
    if [ "$file_count" -eq 0 ]; then
        if [ "$badge_status" = "true" ]; then
            log_info "Badge found but no updates needed for $org/$repo. Skipping."
            REPOS_NO_CHANGES+=("$org/$repo")
        else
            log_warn "No badge found in $org/$repo. Skipping."
            REPOS_WITHOUT_BADGE+=("$org/$repo")
        fi
        return 0
    fi
    
    # Get the SHA of the default branch head
    local base_sha
    base_sha=$(get_default_branch_sha "$org" "$repo" "$default_branch")
    if [ $? -ne 0 ] || [ -z "$base_sha" ]; then
        log_error "Failed to get base SHA for $org/$repo (branch: $default_branch)"
        log_error "   This may indicate the branch doesn't exist, API error, or insufficient permissions"
        REPOS_WITH_ERRORS+=("$org/$repo (failed to get base SHA)")
        return 1
    fi
    log_info "Base SHA validated: ${base_sha:0:7}... (permissions OK)"
    
    # Test write permissions before proceeding (critical for DRY_RUN validation)
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Testing write permissions (creating and deleting test branch)..."
        if ! test_write_permissions "$org" "$repo" "$default_branch" "$base_sha"; then
            log_error "[DRY RUN] Write permission test failed - cannot create branches"
            log_error "   This indicates insufficient permissions or branch protection rules"
            REPOS_WITH_ERRORS+=("$org/$repo (write permission test failed)")
            return 1
        fi
        log_success "[DRY RUN] Write permissions verified - can create branches"
        log_info "[DRY RUN] Proceeding to create branch and files for PR testing"
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
        
        # Create commit message with DCO sign-off (org-specific)
        local commit_msg
        if [ "$SELECTED_ORG" = "finos" ]; then
            commit_msg="Update badge link: stages → maturity in $file_path"
        elif [ "$SELECTED_ORG" = "finos-labs" ]; then
            commit_msg="Update badge to be clickable link in $file_path"
        fi
        
        if [ -n "$current_user_name" ] && [ -n "$current_user_email" ]; then
            commit_msg="$commit_msg

Signed-off-by: $current_user_name <$current_user_email>"
        fi
        
        log_info "Updating file: $file_path"
        if update_file_via_api "$org" "$repo" "$BRANCH_NAME" "$file_path" "$file_content" "$commit_msg" "$file_sha"; then
            files_updated=$((files_updated + 1))
            log_success "Updated $file_path"
        else
            log_error "Failed to update $file_path in $org/$repo"
            # Clean up the branch if file update fails
            log_info "Cleaning up branch $BRANCH_NAME due to file update failure"
            local delete_result
            delete_result=$(api_call_with_error_handling "/repos/$org/$repo/git/refs/heads/$BRANCH_NAME" "$org" "$repo" "delete branch after file update failure" -X DELETE 2>&1)
            if [ $? -eq 0 ]; then
                log_info "Successfully cleaned up branch $BRANCH_NAME"
            else
                log_warn "Could not clean up branch $BRANCH_NAME after file update failure"
            fi
            REPOS_WITH_ERRORS+=("$org/$repo (file update failed: $file_path)")
            return 1
        fi
    done <<< "$files_to_update"
    
    if [ "$files_updated" -eq 0 ]; then
        log_info "No files were updated in $org/$repo. Skipping."
        # Clean up the branch
        log_info "Cleaning up branch $BRANCH_NAME (no changes made)"
        local delete_result
        delete_result=$(api_call_with_error_handling "/repos/$org/$repo/git/refs/heads/$BRANCH_NAME" "$org" "$repo" "delete branch (no changes)" -X DELETE 2>&1)
        if [ $? -eq 0 ]; then
            log_info "Successfully cleaned up branch $BRANCH_NAME"
        else
            log_warn "Could not clean up branch $BRANCH_NAME (may have been deleted already)"
        fi
        REPOS_NO_CHANGES+=("$org/$repo")
        return 0
    fi
    
    # Create pull request
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Testing PR metadata validation (gh pr create --dry-run)..."
        log_warn "[DRY RUN] Note: --dry-run may not test push permissions - write permission test above validates that"
        local pr_test_result
        pr_test_result=$(gh pr create \
            --repo "$org/$repo" \
            --title "$PR_TITLE" \
            --body "$PR_BODY" \
            --head "$BRANCH_NAME" \
            --base "$default_branch" \
            --dry-run 2>&1)
        local pr_test_exit=$?
        
        if [ $pr_test_exit -eq 0 ]; then
            log_success "[DRY RUN] PR metadata validation passed"
            log_info "[DRY RUN] PR test output: $(echo "$pr_test_result" | head -3)"
            log_info "[DRY RUN] Full workflow validated: write permissions ✓, branch creation ✓, file updates ✓, PR metadata ✓"
            REPOS_WITH_CHANGES+=("$org/$repo")
        else
            log_error "[DRY RUN] PR metadata validation failed"
            if echo "$pr_test_result" | grep -qiE "(rate limit|429)"; then
                log_error "   Rate limit error detected"
            elif echo "$pr_test_result" | grep -qiE "(unauthorized|forbidden|401|403)"; then
                log_error "   Authentication/permission error detected"
            else
                log_error "   Error details: $(echo "$pr_test_result" | head -3)"
            fi
        fi
    else
        log_info "Creating pull request for $org/$repo"
        local pr_result
        pr_result=$(gh pr create \
            --repo "$org/$repo" \
            --title "$PR_TITLE" \
            --body "$PR_BODY" \
            --head "$BRANCH_NAME" \
            --base "$default_branch" 2>&1)
        local pr_exit_code=$?
        
        if [ $pr_exit_code -eq 0 ]; then
            log_success "Created PR for $org/$repo"
            PRS_CREATED=$((PRS_CREATED + 1))
            REPOS_WITH_CHANGES+=("$org/$repo")
        else
            log_error "Failed to create PR for $org/$repo"
            # Check if it's a rate limit or auth error
            if echo "$pr_result" | grep -qiE "(rate limit|429)"; then
                log_error "   Rate limit error detected. Consider waiting before retrying."
            elif echo "$pr_result" | grep -qiE "(unauthorized|forbidden|401|403)"; then
                log_error "   Authentication/permission error detected."
            else
                log_error "   Error details: $(echo "$pr_result" | head -3)"
            fi
            # Clean up the branch if PR creation fails
            log_info "Cleaning up branch $BRANCH_NAME due to PR creation failure"
            local delete_result
            delete_result=$(api_call_with_error_handling "/repos/$org/$repo/git/refs/heads/$BRANCH_NAME" "$org" "$repo" "delete branch after PR creation failure" -X DELETE 2>&1)
            if [ $? -eq 0 ]; then
                log_info "Successfully cleaned up branch $BRANCH_NAME"
            else
                log_warn "Could not clean up branch $BRANCH_NAME after PR creation failure"
            fi
            REPOS_WITH_ERRORS+=("$org/$repo (PR creation failed)")
        fi
    fi
        
    log_success "Completed processing for $org/$repo"
    echo ""
}

# =============================================================================
# MAIN PROCESSING LOGIC
# =============================================================================

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
        
        # Get all repositories in the organization (excluding archived ones)
        repos=$(gh repo list "$org" --limit $GITHUB_API_LIMIT --json name,isArchived -q '.[] | select(.isArchived == false) | .name' 2>/dev/null)
        
        if [ -z "$repos" ]; then
            log_warn "No repositories found in organization: $org"
            continue
        fi
        
        repo_count=$(echo "$repos" | wc -l | tr -d ' ')
        log_info "Found $repo_count repositories in $org"
        
        # Check initial rate limit
        log_info "Checking GitHub API rate limit..."
        initial_remaining=$(check_rate_limit 2>/dev/null || echo "unknown")
        if [ "$initial_remaining" != "unknown" ]; then
            log_info "Initial rate limit: $initial_remaining requests remaining"
        fi
        
        # Process each repository
        repo_index=0
        for repo in $repos; do
            repo_index=$((repo_index + 1))
            
            # Check rate limit every 10 repos or if we're getting low
            if [ $((repo_index % 10)) -eq 0 ] || [ "$repo_index" -eq 1 ]; then
                remaining=$(check_rate_limit 2>/dev/null || echo "unknown")
                if [ "$remaining" != "unknown" ]; then
                    log_info "[$repo_index/$repo_count] Rate limit: $remaining requests remaining"
                    # Wait if rate limit is too low
                    wait_for_rate_limit
                fi
            fi
            
            process_repo "$org" "$repo"
        done
    done
fi

log_success "Badge link update process completed!"

# Check final rate limit
log_info "Checking final GitHub API rate limit..."
final_remaining=$(check_rate_limit 2>/dev/null || echo "unknown")
if [ "$final_remaining" != "unknown" ]; then
    log_info "Final rate limit: $final_remaining requests remaining"
fi

# Print summary
echo ""
log_info "=========================================="
log_info "SUMMARY"
log_info "=========================================="
log_success "PRs Created: $PRS_CREATED"

# Report repos that received changes (successfully processed)
if [ ${#REPOS_WITH_CHANGES[@]} -gt 0 ]; then
    echo ""
    log_success "Repositories with changes applied (${#REPOS_WITH_CHANGES[@]} total):"
    for repo in "${REPOS_WITH_CHANGES[@]}"; do
        echo "  ✓ $repo"
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

# Report repos without badges
if [ ${#REPOS_WITHOUT_BADGE[@]} -gt 0 ]; then
    echo ""
    log_warn "Repositories without badges (${#REPOS_WITHOUT_BADGE[@]} total):"
    for repo in "${REPOS_WITHOUT_BADGE[@]}"; do
        echo "  ⚠ $repo"
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

# Report repos with errors
if [ ${#REPOS_WITH_ERRORS[@]} -gt 0 ]; then
    echo ""
    log_error "Repositories with errors (${#REPOS_WITH_ERRORS[@]} total):"
    for repo in "${REPOS_WITH_ERRORS[@]}"; do
        echo "  ✗ $repo"
    done
fi

# Report repos with insufficient access
if [ ${#INSUFFICIENT_ACCESS_REPOS[@]} -gt 0 ]; then
    echo ""
    log_warn "Repositories with insufficient access (${#INSUFFICIENT_ACCESS_REPOS[@]} total):"
    for repo in "${INSUFFICIENT_ACCESS_REPOS[@]}"; do
        echo "  ✗ $repo"
    done
fi

echo ""
log_info "=========================================="
