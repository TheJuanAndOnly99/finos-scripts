# FINOS Labs Hackathon Scripts - Configuration System

This document explains the new centralized configuration system for FINOS Labs hackathon repository management scripts.

## Overview

The configuration system provides:
- **Centralized settings** - All configuration in one place (`config.sh`)
- **Command-line parameters** - Scripts accept options for flexibility
- **Structured logging** - Consistent logging with timestamps and levels
- **Validation functions** - Built-in checks for authentication, organizations, teams
- **Reusability** - Easy to adapt for different hackathons

## Configuration File (`config.sh`)

The `config.sh` file contains all configuration variables organized into sections:

### Organization Settings
```bash
export ORG="finos-labs"
```

### Hackathon Settings
```bash
export HACKATHON_NAME="learnaix-h-2025"
export HACKATHON_PREFIX="learnaix-h-2025"
export TEMPLATE_REPO="learnaix-h-2025"
```

### Team Settings
```bash
export FINOS_STAFF_TEAM="finos-staff"
export FINOS_ADMINS_TEAM="finos-admins"
export JUDGES_TEAM="${HACKATHON_PREFIX}-judges-team"
```

### User Management
```bash
export REMOVE_USER="TheJuanAndOnly99"
export DEFAULT_ADMINS=("finos-admin")
```

## Usage Examples

### Basic Usage
```bash
# Run with default configuration
./add-team-to-repo.sh

# Specify different team and role
./add-team-to-repo.sh --team "custom-team" --role "maintain"

# Add different admin users
./add-admins.sh --users "user1,user2,user3"
```

### Command Line Options

#### `add-team-to-repo.sh`
- `-t, --team TEAM_NAME` - Team to add to repositories (default: judges team)
- `-r, --role ROLE` - Permission role (default: triage)
- `-h, --help` - Show help message

Available roles: `read`, `triage`, `write`, `maintain`, `admin`

#### `add-admins.sh`
- `-u, --users USER1,USER2,...` - Comma-separated list of admin users
- `-h, --help` - Show help message

## Logging

All scripts now use structured logging with timestamps:

```
[2025-01-27 10:30:15] [INFO] Adding team 'learnaix-h-2025-judges-team' with 'triage' permission
[2025-01-27 10:30:16] [SUCCESS] Team 'learnaix-h-2025-judges-team' verified
[2025-01-27 10:30:17] [ERROR] Failed to update team access on repository
```

Log files are stored in `./logs/hackathon-YYYYMMDD.log`

## Validation Functions

The configuration system includes built-in validation:

- `check_github_auth()` - Verifies GitHub CLI authentication
- `check_org_exists()` - Checks if organization exists
- `check_template_exists()` - Validates template repository
- `check_team_exists(team)` - Checks if team exists

## Utility Functions

- `slugify(text)` - Converts text to GitHub team slug format
- `generate_team_name(repo)` - Generates team name from repository name
- `generate_repo_name(team)` - Generates repository name from team name

## Adapting for Different Hackathons

To use these scripts for a different hackathon:

1. **Update `config.sh`**:
   ```bash
   export HACKATHON_NAME="new-hackathon-2025"
   export HACKATHON_PREFIX="new-hackathon-2025"
   export TEMPLATE_REPO="new-hackathon-2025"
   ```

2. **Update team names**:
   ```bash
   export JUDGES_TEAM="${HACKATHON_PREFIX}-judges-team"
   ```

3. **Update user lists**:
   ```bash
   export DEFAULT_ADMINS=("new-admin1" "new-admin2")
   export REMOVE_USER="your-username"
   ```

## Testing the Configuration

Run the demo script to test your configuration:

```bash
./demo-config.sh
```

This will:
- Initialize the configuration
- Show current settings
- List repositories for the hackathon
- Check team existence
- Demonstrate logging

## Migration from Old Scripts

The refactored scripts maintain backward compatibility while adding new features:

- **Old way**: Hardcoded values in each script
- **New way**: Centralized configuration with command-line options

You can still run scripts without parameters to use defaults, or specify options for flexibility.

## Next Steps

This configuration system enables:
- Easy adaptation for different hackathons
- Better error handling and logging
- Command-line flexibility
- Consistent behavior across scripts

Future enhancements could include:
- Environment-specific configurations
- Dry-run modes
- Parallel processing
- Configuration validation
