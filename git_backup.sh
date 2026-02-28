#!/bin/bash

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

cd /config
git add .
if ! git diff-index --quiet HEAD -- 2>/dev/null; then
  git commit -m "Auto backup: $(date +'%Y-%m-%d %H:%M:%S')"
  if git pull --rebase origin main; then
    if git push origin main; then
      notify ":floppy_disk: Config backed up to GitHub successfully."
      echo "Backup completed successfully"
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
