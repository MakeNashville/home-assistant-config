#!/bin/bash
# Writes a list of opted-in entities to entity_list.txt.
# To include an entity, apply the "entity_list" label to it in
# Settings > Labels, then tag the entity via its settings page.
python3 -c "
import json, sys

registry = '/config/.storage/core.entity_registry'
try:
    with open(registry) as f:
        data = json.load(f)
except FileNotFoundError:
    print(f'ERROR: {registry} not found', file=sys.stderr)
    sys.exit(1)
except json.JSONDecodeError as e:
    print(f'ERROR: could not parse {registry}: {e}', file=sys.stderr)
    sys.exit(1)

entities = sorted(
    (e for e in data['data']['entities'] if 'entity_list' in e.get('labels', [])),
    key=lambda e: e['entity_id']
)
with open('/config/entity_list.txt', 'w') as out:
    for e in entities:
        name = e.get('name') or e.get('original_name', '')
        out.write(f\"{e['entity_id']} | {name}\n\")
print(f'Wrote {len(entities)} entities to entity_list.txt')
"
