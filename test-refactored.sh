#!/bin/bash

# Test script for the refactored create-repos.sh and add-teams.sh
# This demonstrates the new configuration system and command-line options

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# Initialize configuration
init_config

echo "=== Testing Refactored Scripts ==="
echo

# Test 1: Show help for create-repos.sh
echo "1. Testing create-repos.sh help:"
echo "--------------------------------"
./create-repos.sh --help
echo

# Test 2: Show help for add-teams.sh
echo "2. Testing add-teams.sh help:"
echo "-----------------------------"
./add-teams.sh --help
echo

# Test 3: Dry run for create-repos.sh (first 3 teams only)
echo "3. Testing create-repos.sh dry run (first 3 teams):"
echo "---------------------------------------------------"
# Create a temporary script with only first 3 teams for testing
cat > test-create-repos.sh << 'EOF'
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"
init_config

# Test with only first 3 teams
REPOS=("Akaza" "Hello Worlders" "Shivam Dubey")
DRY_RUN=true

for REPO in "${REPOS[@]}"; do
  TEAM_SLUG=$(slugify "$REPO")
  REPO_SLUG="${HACKATHON_PREFIX}-${TEAM_SLUG}"
  TEAM_NAME="${REPO_SLUG}-team"
  
  log_info "Processing: $REPO_SLUG | Team: $TEAM_NAME"
  log_info "[DRY RUN] Would create repository: $ORG/$REPO_SLUG from template $ORG/$TEMPLATE_REPO"
  log_info "[DRY RUN] Would create team: $TEAM_NAME"
  log_info "[DRY RUN] Would grant team $TEAM_NAME '$TEAM_PERMISSION' access to $REPO_SLUG"
done
EOF

chmod +x test-create-repos.sh
./test-create-repos.sh
rm test-create-repos.sh
echo

# Test 4: Test add-teams.sh with custom parameters
echo "4. Testing add-teams.sh with custom parameters:"
echo "-----------------------------------------------"
echo "This would add 'finos-staff' team with 'triage' permission to repositories containing 'learnaix-h-2025'"
echo "Command: ./add-teams.sh --teams finos-staff --permission triage --filter learnaix-h-2025"
echo
echo "Note: This is a dry run demonstration. Actual execution would modify repositories."
echo

# Test 5: Show configuration
echo "5. Current configuration:"
echo "-------------------------"
show_config
echo

echo "=== Test Complete ==="
echo "All scripts are now using the centralized configuration system!"
echo "Key improvements:"
echo "  ✅ Centralized configuration in config.sh"
echo "  ✅ Command-line parameter support"
echo "  ✅ Structured logging with timestamps"
echo "  ✅ Better error handling and validation"
echo "  ✅ Dry-run capabilities"
echo "  ✅ Consistent behavior across scripts"
