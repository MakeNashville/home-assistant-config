#!/bin/bash
# Writes a list of opted-in entities to entity_list.txt, then snapshots
# new entities into entity_snapshots.json for local preview.
#
# To include an entity, apply the "entity_list" label to it in
# Settings > Labels, then tag the entity via its settings page.

set -euo pipefail

REGISTRY="/config/.storage/core.entity_registry"
SNAPSHOTS_FILE="/config/entity_snapshots.json"
BLOCKLIST_FILE="/config/snapshot_blocklist.json"
HA_API="http://supervisor/core/api"

if [ ! -f "$REGISTRY" ]; then
  echo "ERROR: $REGISTRY not found" >&2
  exit 1
fi

# ── Step 1: Write entity_list.txt (existing behavior) ────────────────

count=$(jq -r '
  .data.entities
  | map(select((.labels // []) | contains(["entity_list"])))
  | sort_by(.entity_id)
  | .[]
  | "\(.entity_id) | \(.name // .original_name // "")"
' "$REGISTRY" | tee /config/entity_list.txt | wc -l)

echo "Wrote ${count} entities to entity_list.txt"

# ── Step 2: Snapshot new entities for local preview ───────────────────

if [ -z "${SUPERVISOR_TOKEN:-}" ]; then
  echo "SUPERVISOR_TOKEN not set — skipping snapshot generation"
  exit 0
fi

# Load existing snapshots or start empty
if [ -f "$SNAPSHOTS_FILE" ]; then
  existing=$(cat "$SNAPSHOTS_FILE")
else
  existing="{}"
fi

# Load blocklist
if [ -f "$BLOCKLIST_FILE" ]; then
  blocklist=$(cat "$BLOCKLIST_FILE")
else
  blocklist='{"state_patterns":[],"strip_attributes":[]}'
fi

# Fetch all entity states from HA in one call
all_states=$(curl -sf \
  -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
  "${HA_API}/states") || {
  echo "WARNING: Could not fetch entity states — skipping snapshot generation"
  exit 0
}

# Build a lookup map: entity_id -> {state, attributes}
states_map=$(echo "$all_states" | jq '
  map({key: .entity_id, value: {state: .state, attributes: .attributes}})
  | from_entries
')

# Collect entity IDs from entity_list.txt
entity_ids=$(cut -d'|' -f1 /config/entity_list.txt | tr -d ' ')

# Find new entities (not already in snapshots)
new_count=0
updated="$existing"

for entity_id in $entity_ids; do
  # Skip if already snapshotted
  if echo "$updated" | jq -e --arg id "$entity_id" 'has($id)' > /dev/null 2>&1; then
    continue
  fi

  # Get state from the API response
  entry=$(echo "$states_map" | jq --arg id "$entity_id" '.[$id] // empty')
  if [ -z "$entry" ]; then
    continue
  fi

  # Apply blocklist: replace state if entity matches a pattern
  state=$(echo "$entry" | jq -r '.state')
  for i in $(seq 0 $(( $(echo "$blocklist" | jq '.state_patterns | length') - 1 ))); do
    glob=$(echo "$blocklist" | jq -r ".state_patterns[$i].entity_glob")
    replacement=$(echo "$blocklist" | jq -r ".state_patterns[$i].replacement")

    # Convert glob to regex: * -> .*, ? -> .
    regex=$(echo "$glob" | sed 's/\./\\./g; s/\*/.*/g; s/\?/./g')
    regex="^${regex}$"

    if echo "$entity_id" | grep -qE "$regex"; then
      entry=$(echo "$entry" | jq --arg r "$replacement" '.state = $r')
      break
    fi
  done

  # Strip blocklisted attributes
  strip_keys=$(echo "$blocklist" | jq -r '.strip_attributes[]')
  for key in $strip_keys; do
    entry=$(echo "$entry" | jq --arg k "$key" 'del(.attributes[$k])')
  done

  updated=$(echo "$updated" | jq --arg id "$entity_id" --argjson data "$entry" '. + {($id): $data}')
  new_count=$((new_count + 1))
done

# Write updated snapshots (sorted by key)
echo "$updated" | jq -S . > "$SNAPSHOTS_FILE"
echo "Snapshots: ${new_count} new entities added ($(echo "$updated" | jq 'length') total)"
