#!/bin/bash
# Commits changed config files, pushes to the ha-backup branch, and opens
# (or surfaces) a PR to main. Requires a GitHub PAT at /config/.github_token
# with repo scope to create PRs.

set -euo pipefail

GITHUB_TOKEN_FILE="/config/.github_token"
BACKUP_BRANCH="ha-backup"

notify() {
  local msg="$1"
  [ -z "${SUPERVISOR_TOKEN:-}" ] && return
  local body
  body=$(jq -n --arg msg "$msg" \
    '{"message": $msg, "target": "#deployment-feed", "data": {"username": "Git Backup", "icon": "floppy_disk"}}')
  curl -sf -X POST \
    -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$body" \
    http://supervisor/core/api/services/notify/make_nashville || true
}

open_or_find_pr() {
  local github_token="$1"
  local remote_url
  remote_url=$(git remote get-url origin)

  # Extract owner/repo from HTTPS or SSH remote URL
  local owner_repo
  if [[ "$remote_url" =~ github\.com[:/](.+/.+?)(\.git)?$ ]]; then
    owner_repo="${BASH_REMATCH[1]}"
  else
    echo "WARNING: Could not parse GitHub remote URL, skipping PR"
    return
  fi

  local owner="${owner_repo%%/*}"
  local short_sha
  short_sha=$(git rev-parse --short HEAD)
  local commit_msg
  commit_msg=$(git log -1 --pretty=%s)

  local pr_body
  pr_body=$(jq -n \
    --arg title "HA Config Backup: ${commit_msg}" \
    --arg body "Automated config backup from Home Assistant.\n\nLatest commit: \`${short_sha}\` — ${commit_msg}" \
    --arg head "$BACKUP_BRANCH" \
    --arg base "main" \
    '{"title": $title, "body": $body, "head": $head, "base": $base}')

  local response
  response=$(curl -s -X POST \
    -H "Authorization: Bearer $github_token" \
    -H "Content-Type: application/json" \
    -d "$pr_body" \
    "https://api.github.com/repos/${owner_repo}/pulls")

  local pr_url
  pr_url=$(echo "$response" | jq -r '.html_url // empty')

  if [ -n "$pr_url" ]; then
    echo "PR opened: $pr_url"
    notify ":arrow_up: Config backup PR opened: ${pr_url}"
    return
  fi

  # PR already exists — find and surface it
  pr_url=$(curl -s \
    -H "Authorization: Bearer $github_token" \
    "https://api.github.com/repos/${owner_repo}/pulls?head=${owner}:${BACKUP_BRANCH}&base=main&state=open" \
    | jq -r '.[0].html_url // empty')

  if [ -n "$pr_url" ]; then
    echo "PR already open: $pr_url"
    notify ":floppy_disk: Config backed up to GitHub. PR already open: ${pr_url}"
  else
    echo "WARNING: Could not create or find PR"
    notify ":floppy_disk: Config backed up to GitHub (could not open PR)."
  fi
}

if [ ! -f "$GITHUB_TOKEN_FILE" ]; then
  echo "ERROR: No GitHub token found at $GITHUB_TOKEN_FILE" >&2
  notify ":warning: Config backup failed — no GitHub token at /config/.github_token."
  exit 1
fi
GITHUB_TOKEN=$(cat "$GITHUB_TOKEN_FILE")

# Inline credential helper so git never prompts for a username/password
GIT_AUTH=(-c "credential.helper=!f() { echo username=oauth2; echo password=${GITHUB_TOKEN}; }; f")

cd /config
git add .

if ! git diff-index --quiet HEAD -- 2>/dev/null; then
  git commit -a -m "Auto backup: $(date +'%Y-%m-%d %H:%M:%S')"

  if git "${GIT_AUTH[@]}" pull --rebase origin main; then
    if git "${GIT_AUTH[@]}" push --force origin HEAD:"$BACKUP_BRANCH"; then
      echo "Backup pushed to $BACKUP_BRANCH"

      open_or_find_pr "$GITHUB_TOKEN"
    else
      notify ":warning: Config backup failed — push error. Manual intervention may be required."
      echo "Backup failed: push error"
      exit 1
    fi
  else
    git rebase --abort
    notify ":warning: Config backup failed — rebase conflict. Manual intervention may be required."
    echo "Backup failed: rebase conflict"
    exit 1
  fi
else
  echo "No changes to commit"
fi
