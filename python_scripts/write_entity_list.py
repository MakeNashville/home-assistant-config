with open("/config/entity_list.txt", "w") as f:
    for state in sorted(hass.states.async_all(), key=lambda s: s.entity_id):
        f.write(f"{state.entity_id} | {state.name}\n")
