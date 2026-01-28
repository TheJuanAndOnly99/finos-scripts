#!/bin/bash

# FINOS Labs Hackathon Configuration
# This file contains all configuration variables for hackathon repository management scripts

# =============================================================================
# ORGANIZATION SETTINGS
# =============================================================================
export ORG="finos-labs"

# =============================================================================
# HACKATHON SETTINGS
# =============================================================================
# Current hackathon configuration
export HACKATHON_NAME="learnaix-h-2025"
export HACKATHON_PREFIX="learnaix-h-2025"
export TEMPLATE_REPO="learnaix-h-2025"

# Previous hackathon configurations (for reference)
export PREVIOUS_HACKATHON_NAME="dtcch-2025"
export PREVIOUS_HACKATHON_PREFIX="dtcch"

# =============================================================================
# TEAM SETTINGS
# =============================================================================
# Core FINOS teams
export FINOS_STAFF_TEAM="finos-staff"
export FINOS_ADMINS_TEAM="finos-admins"

# Hackathon-specific teams
export JUDGES_TEAM="${HACKATHON_PREFIX}-judges-team"

# Team permissions
export STAFF_PERMISSION="triage"
export ADMINS_PERMISSION="maintain"
export JUDGES_PERMISSION="triage"
export TEAM_PERMISSION="admin"

# =============================================================================
# REPOSITORY SETTINGS
# =============================================================================
# Repository visibility
export DEFAULT_VISIBILITY="private"  # private, public, internal

# Branch protection settings
export BRANCH_PROTECTION_JSON='{
  "required_status_checks": null,
  "enforce_admins": false,
  "required_pull_request_reviews": {
    "required_approving_review_count": 1
  },
  "restrictions": null,
  "require_signatures": true
}'

# =============================================================================
# USER MANAGEMENT
# =============================================================================
# User to remove from teams after creation (usually the script runner)
export REMOVE_USER="TheJuanAndOnly99"

# Default admin users for repositories
export DEFAULT_ADMINS=("finos-admin")

# =============================================================================
# API SETTINGS
# =============================================================================
# GitHub API settings
export GITHUB_API_LIMIT=1000
export API_TIMEOUT=30

# =============================================================================
# LOGGING SETTINGS
# =============================================================================
export LOG_DIR="./logs"
export LOG_FILE="${LOG_DIR}/hackathon-$(date '+%Y%m%d').log"

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Create log directory if it doesn't exist
mkdir -p "$LOG_DIR"

# Logging function
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# Log info messages
log_info() {
    log "INFO" "$1"
}

# Log warning messages
log_warn() {
    log "WARN" "$1"
}

# Log error messages
log_error() {
    log "ERROR" "$1"
}

# Log success messages
log_success() {
    log "SUCCESS" "$1"
}

# =============================================================================
# VALIDATION FUNCTIONS
# =============================================================================

# Check if GitHub CLI is authenticated
check_github_auth() {
    if ! gh auth status &>/dev/null; then
        log_error "GitHub CLI is not authenticated. Please run 'gh auth login' first."
        exit 1
    fi
    log_info "GitHub CLI authentication verified"
}

# Check if organization exists
check_org_exists() {
    if ! gh api "/orgs/$ORG" &>/dev/null; then
        log_error "Organization '$ORG' does not exist or is not accessible"
        exit 1
    fi
    log_info "Organization '$ORG' verified"
}

# Check if template repository exists
check_template_exists() {
    if ! gh api "/repos/$ORG/$TEMPLATE_REPO" &>/dev/null; then
        log_error "Template repository '$ORG/$TEMPLATE_REPO' does not exist"
        exit 1
    fi
    log_info "Template repository '$ORG/$TEMPLATE_REPO' verified"
}

# Check if team exists
check_team_exists() {
    local team="$1"
    if ! gh api "/orgs/$ORG/teams/$team" &>/dev/null; then
        log_warn "Team '$team' does not exist in organization '$ORG'"
        return 1
    fi
    return 0
}

# =============================================================================
# COMMON FUNCTIONS
# =============================================================================

# Slugify team names (convert to GitHub team slug format)
slugify() {
    echo "$1" \
        | tr '[:upper:]' '[:lower:]' \
        | tr ' +' '-' \
        | tr -d "'" \
        | sed 's/-$//'
}

# Generate team name from repository name
generate_team_name() {
    local repo_name="$1"
    local slug=$(slugify "$repo_name")
    echo "${slug}-team"
}

# Generate repository name from team name
generate_repo_name() {
    local team_name="$1"
    local slug=$(slugify "$team_name")
    echo "${HACKATHON_PREFIX}-${slug}"
}

# =============================================================================
# INITIALIZATION
# =============================================================================

# Initialize configuration
init_config() {
    log_info "Initializing hackathon configuration for '$HACKATHON_NAME'"
    check_github_auth
    check_org_exists
    check_template_exists
    
    log_success "Configuration initialized successfully"
    log_info "Organization: $ORG"
    log_info "Hackathon: $HACKATHON_NAME"
    log_info "Template: $TEMPLATE_REPO"
}

# =============================================================================
# RATE LIMIT HANDLING
# =============================================================================
# Rate limit thresholds (as percentage of remaining quota)
export RATE_LIMIT_WARN_THRESHOLD=20  # Warn when below 20% remaining
export RATE_LIMIT_PAUSE_THRESHOLD=10 # Pause when below 10% remaining
export RATE_LIMIT_RETRY_MAX=3        # Max retries for rate limit errors
export RATE_LIMIT_RETRY_DELAY=60     # Initial retry delay in seconds

# Function to check current GitHub API rate limit status
# Returns: remaining requests (to stdout), exit code 0 on success
check_rate_limit() {
    local rate_limit_info=$(gh api rate_limit --jq '.resources.core' 2>/dev/null)
    if [ -z "$rate_limit_info" ]; then
        return 1
    fi
    
    local remaining=$(echo "$rate_limit_info" | jq -r '.remaining' 2>/dev/null)
    local limit=$(echo "$rate_limit_info" | jq -r '.limit' 2>/dev/null)
    local reset_time=$(echo "$rate_limit_info" | jq -r '.reset' 2>/dev/null)
    
    if [ -z "$remaining" ] || [ "$remaining" = "null" ]; then
        return 1
    fi
    
    # Output remaining count
    echo "$remaining"
    
    # Calculate percentage
    if [ -n "$limit" ] && [ "$limit" != "null" ] && [ "$limit" -gt 0 ]; then
        local percentage=$((remaining * 100 / limit))
        
        # Log warning if below threshold
        if [ "$percentage" -lt "$RATE_LIMIT_PAUSE_THRESHOLD" ]; then
            # Convert Unix timestamp to readable date (works on both Linux and macOS)
            local reset_date
            if date -r "$reset_time" '+%Y-%m-%d %H:%M:%S' &>/dev/null 2>&1; then
                reset_date=$(date -r "$reset_time" '+%Y-%m-%d %H:%M:%S' 2>/dev/null)
            else
                reset_date=$(date -d "@$reset_time" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "unknown")
            fi
            log_warn "⚠️  Rate limit low: $remaining/$limit remaining (${percentage}%)"
            log_warn "   Rate limit resets at: $reset_date"
            return 2  # Special exit code for pause threshold
        elif [ "$percentage" -lt "$RATE_LIMIT_WARN_THRESHOLD" ]; then
            log_warn "Rate limit getting low: $remaining/$limit remaining (${percentage}%)"
        fi
    fi
    
    return 0
}

# Function to wait if rate limit is too low
# Returns: 0 if OK to proceed, 1 if should wait
wait_for_rate_limit() {
    local remaining=$(check_rate_limit)
    local exit_code=$?
    
    if [ $exit_code -eq 2 ]; then
        # Below pause threshold - wait until reset
        local rate_limit_info=$(gh api rate_limit --jq '.resources.core' 2>/dev/null)
        local reset_time=$(echo "$rate_limit_info" | jq -r '.reset' 2>/dev/null)
        local current_time=$(date +%s)
        local wait_seconds=$((reset_time - current_time + 10))  # Add 10s buffer
        
        if [ "$wait_seconds" -gt 0 ]; then
            log_warn "Rate limit too low. Waiting ${wait_seconds}s until reset..."
            sleep "$wait_seconds"
            log_info "Rate limit reset. Continuing..."
        fi
    elif [ $exit_code -ne 0 ]; then
        log_warn "Could not check rate limit. Proceeding with caution..."
    fi
    
    return 0
}

# Function to retry API call with exponential backoff on rate limit errors
# Usage: retry_on_rate_limit "gh api ..." [max_retries] [initial_delay]
# Returns: exit code from final attempt
retry_on_rate_limit() {
    local api_command="$1"
    local max_retries="${2:-$RATE_LIMIT_RETRY_MAX}"
    local delay="${3:-$RATE_LIMIT_RETRY_DELAY}"
    local attempt=1
    
    while [ $attempt -le $max_retries ]; do
        # Check rate limit before attempting
        local remaining=$(check_rate_limit 2>/dev/null)
        if [ $? -eq 2 ]; then
            wait_for_rate_limit
        fi
        
        # Execute the command
        eval "$api_command"
        local exit_code=$?
        
        # If successful or not a rate limit error, return
        if [ $exit_code -eq 0 ]; then
            return 0
        fi
        
        # Check if it's a rate limit error (would need to capture stderr)
        # For now, we'll use a simpler approach: check rate limit and retry if low
        if [ $attempt -lt $max_retries ]; then
            local remaining=$(check_rate_limit 2>/dev/null)
            if [ $? -eq 2 ] || [ "${remaining:-0}" -lt 100 ]; then
                log_warn "Rate limit issue detected. Waiting ${delay}s before retry (attempt $attempt/$max_retries)..."
                sleep "$delay"
                delay=$((delay * 2))  # Exponential backoff
            fi
        fi
        
        attempt=$((attempt + 1))
    done
    
    return $exit_code
}

# =============================================================================

show_config() {
    echo "=== FINOS Labs Hackathon Configuration ==="
    echo "Organization: $ORG"
    echo "Hackathon Name: $HACKATHON_NAME"
    echo "Hackathon Prefix: $HACKATHON_PREFIX"
    echo "Template Repository: $TEMPLATE_REPO"
    echo "Judges Team: $JUDGES_TEAM"
    echo "Staff Teams: $FINOS_STAFF_TEAM, $FINOS_ADMINS_TEAM"
    echo "Log File: $LOG_FILE"
    echo "=========================================="
}

# Show usage if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    show_config
fi
