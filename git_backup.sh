#!/bin/bash
cd /config
git add .
if ! git diff-index --quiet HEAD -- 2>/dev/null; then
  git commit -m "Auto backup: $(date +'%Y-%m-%d %H:%M:%S')"
  git push origin main
  echo "Backup completed successfully"
else
  echo "No changes to commit"
fi
