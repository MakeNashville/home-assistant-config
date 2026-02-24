#!/bin/bash

notify() {
  local msg="$1"
  [ -z "${SUPERVISOR_TOKEN:-}" ] && return
  curl -sf -X POST \
    -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"message\":\"$msg\",\"target\":\"#facilities-feed\",\"data\":{\"username\":\"Git Backup\",\"icon\":\"floppy_disk\"}}" \
    http://supervisor/core/api/services/notify/make_nashville || true
}

cd /config
git add .
if ! git diff-index --quiet HEAD -- 2>/dev/null; then
  git commit -m "Auto backup: $(date +'%Y-%m-%d %H:%M:%S')"
  if git pull --rebase origin main && git push origin main; then
    notify "Config backed up successfully."
    echo "Backup completed successfully"
  else
    notify "⚠️ Config backup failed — git pull or push error. Manual intervention may be required."
    echo "Backup failed"
    exit 1
  fi
else
  echo "No changes to commit"
fi
