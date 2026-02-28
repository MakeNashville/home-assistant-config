#!/bin/bash
python3 -c "
import json
with open('/config/.storage/core.entity_registry') as f:
    data = json.load(f)
entities = sorted(data['data']['entities'], key=lambda e: e['entity_id'])
with open('/config/entity_list.txt', 'w') as out:
    for e in entities:
        name = e.get('name') or e.get('original_name', '')
        out.write(f\"{e['entity_id']} | {name}\n\")
"
