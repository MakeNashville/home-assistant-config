#!/bin/bash
# One-time script to apply the "entity_list" label to opted-in entities.
# Run this from the SSH add-on: bash /config/setup_entity_labels.sh
#
# Requires SUPERVISOR_TOKEN to be set (automatic when run inside the HA container).

set -euo pipefail

if [ -z "${SUPERVISOR_TOKEN:-}" ]; then
  echo "ERROR: SUPERVISOR_TOKEN is not set. Run this from the SSH add-on inside the HA container." >&2
  exit 1
fi

HA_API="http://supervisor/core/api"
LABEL="entity_list"

ENTITIES=(
  "sensor.huckleberry_prints_completed_week"
  "sensor.huckleberry_prints_failed_week"
  "sensor.kiwi_prints_completed_week"
  "sensor.kiwi_prints_failed_week"
  "sensor.mango_prints_completed_week"
  "sensor.mango_prints_failed_week"
  "sensor.papaya_prints_completed_week"
  "sensor.papaya_prints_failed_week"
  "sensor.pineapple_prints_completed_week"
  "sensor.pineapple_prints_failed_week"
  "sensor.strawberry_prints_completed_week"
  "sensor.strawberry_prints_failed_week"
)

for entity_id in "${ENTITIES[@]}"; do
  current=$(curl -sf \
    -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
    "${HA_API}/config/entity_registry/${entity_id}" || true)

  if [ -z "$current" ]; then
    echo "SKIP: ${entity_id} not found in entity registry"
    continue
  fi

  updated_labels=$(echo "$current" | jq --arg label "$LABEL" '.labels + [$label] | unique')

  curl -sf -X POST \
    -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --argjson labels "$updated_labels" '{"labels": $labels}')" \
    "${HA_API}/config/entity_registry/${entity_id}" > /dev/null

  echo "OK:   ${entity_id}"
done

echo ""
echo "Done. Run write_entity_list.sh to verify the output."
