# scripts

Shell scripts to help manage GitHub org/repo automation (teams, users, repo creation, badges, maintainers).

## What’s in here

- **Configuration**: `config.sh` (centralized settings + logging + validation helpers)
- **Docs**: `CONFIGURATION.md`
- **Common scripts**:
  - `create-repos.sh`: create repos from a template + apply branch protection + create teams
  - `add-teams.sh`, `add-team-to-repo.sh`: grant team access to repos
  - `add-users.sh`, `add-admins.sh`: add users/admins
  - `add-maintainers-file.sh`: open PRs adding `MAINTAINERS.md`
  - `update-finos-badges*.sh`: update badges
  - `delete-github-packages.sh`: delete GitHub Packages (requires `GITHUB_PAT`)

## Prerequisites

- `bash`
- GitHub CLI: `gh` (authenticated via `gh auth login`)
- `jq` (some scripts parse JSON)
- `curl` (used by some scripts)

## Quick start

1. Review and edit config:

   - `config.sh` (org name, hackathon prefix, template repo, etc.)

2. Run a script (many support `--help` and/or `--dry-run`):

   - `./create-repos.sh --help`
   - `./create-repos.sh --dry-run`

## Notes

- Runtime output is written under `./logs/` and is intentionally gitignored.
- `delete-github-packages.sh` expects a token in `GITHUB_PAT` (do not commit tokens).

