#!/bin/bash
# Writes a list of opted-in entities to entity_list.txt.
# To include an entity, apply the "entity_list" label to it in
# Settings > Labels, then tag the entity via its settings page.

REGISTRY="/config/.storage/core.entity_registry"

if [ ! -f "$REGISTRY" ]; then
  echo "ERROR: $REGISTRY not found" >&2
  exit 1
fi

count=$(jq -r '
  .data.entities
  | map(select(.labels | index("entity_list")))
  | sort_by(.entity_id)
  | .[]
  | "\(.entity_id) | \(.name // .original_name // "")"
' "$REGISTRY" | tee /config/entity_list.txt | wc -l)

echo "Wrote ${count} entities to entity_list.txt"
