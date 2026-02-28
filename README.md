# MakeNashville Home Assistant Config

Home Assistant configuration for the [MakeNashville](https://makenashville.org) makerspace.
Manages 3D printer lifecycle notifications, facilities monitoring, air quality alerting, and automated config backup.

---

## Repository layout

```
.
├── automations/
│   ├── printers.yaml         # 3D printer lifecycle, roundup, weekly summary, offline
│   ├── facilities.yaml       # Facilities Pulse + Air Quality alerts
│   ├── kaeser.yaml           # Kaeser compressor notifications + history purge
│   ├── webhooks.yaml         # Stripe filament purchase + OctoEverywhere Gadget
│   └── backup.yaml           # Nightly config backup to GitHub
├── configuration.yaml        # Core HA config: recorder, template sensors,
│                             #   input helpers, shell commands
├── secrets.yaml              # ⛔ Not committed — see Secrets
├── git_backup.sh             # Backup script: commits config, pushes to ha-backup branch
├── write_entity_list.sh      # Regenerates entity_list.txt from the entity_list label
├── entity_list.txt           # Auto-generated entity ID reference — do not edit by hand
│
├── dashboards/
│   ├── air_quality.yaml      # Air quality dashboard (3D print room)
│   └── facilities.yaml       # Facilities overview dashboard
│
├── esphome/
│   ├── kaeser-monitor.yaml   # Kaeser air compressor pressure/switch sensor
│   └── secrets.yaml          # ⛔ Not committed — see Secrets
│
├── blueprints/               # Automation blueprints
│
└── .github/workflows/
    ├── validate-yaml.yml     # YAML lint check on every PR (required to merge)
    └── deploy.yml            # Auto-deploy to HA on merge to main
```

---

## Systems

### 3D printers — Lifecycle notifications
Six printers post to `#3dprint-info` via Slack on key state transitions: starting, progress milestones (layer 2, 10, 50%, 90%), finished, stopped, paused, error, and offline. A bi-hourly roundup posts active printer status (suppressed midnight–7am). A weekly summary posts Sunday at 9am.

Printer names follow a fruit convention. Bambu Lab printers (Kiwi, Mango, Papaya, Strawberry, Huckleberry) use the Bambu integration. Pineapple is a Prusa printer via the Prusa integration. Dragonfruit is an additional printer.

### Facilities Pulse
Posts to `#facilities-feed` when any monitored space goes out of range:
- Temperature below 62°F or above 82°F (sustained 5 min)
- Kaeser pressure below 80 psi (sustained 5 min)
- Power alarm or water leak state change

Includes a 15-minute cooldown and a 5°F magnitude guard to suppress sensor noise. An opt-in hourly verbose mode is toggled from the Facilities dashboard.

Environment data is pulled dynamically via the `facilities_pulse` HA label — tag any climate sensor device with that label and it appears automatically in pulse messages and the dashboard.

### Air Quality
AirGradient sensor in the 3D print room. Alerts post to `#facilities-feed` when overall status degrades to Poor or Dangerous (sustained 3 min), with active printer context included. Recovery alerts fire when status returns to Good or Moderate (sustained 5 min).

### Kaeser compressor
Pressure and switch state monitored via ESPHome on an ESP32-C6 Feather. Overpressurization events notify Tim via mobile push and `#facilities-feed`.

### Config backup
Runs nightly at 3am via the SSH addon. Checks out the `ha-backup` branch, merges `main`, commits any changed files, pushes to `ha-backup`, and opens (or surfaces) a PR back to `main`. On success, posts to `#deployment-feed`.

### Entity list
Before each backup, `write_entity_list.sh` regenerates `/config/entity_list.txt` with opted-in entities:

```
sensor.air_quality_carbon_dioxide | Air Quality Carbon Dioxide
sensor.kiwi_print_status | Kiwi Print Status
...
```

To add an entity, apply the `entity_list` label in HA > Settings > Labels, then tag the entity via its settings page.

This file is committed to the repo. It's the primary reference for contributors who need entity IDs without direct HA access — use it when writing automations, templates, or dashboard cards. Do not edit it by hand.

---

## Branch and deploy workflow

```
feature branch → PR → YAML check passes → merge to main → auto-deploy
```

1. **Branch off `main`** — `main` is protected; direct pushes are blocked.
2. **Open a PR** — the `validate-yaml.yml` workflow runs immediately and must pass.
3. **Merge** — `deploy.yml` triggers on merge, pulls the new config onto the HA host, validates it, and reloads all relevant subsystems.
4. **Deployment status** posts to `#deployment-feed` on success or failure.

---

## Secrets

Neither `secrets.yaml` nor `esphome/secrets.yaml` is committed to the repo. Both are gitignored. Each file must be created manually on the HA host.

**`/config/secrets.yaml`**
```yaml
stripe_webhook_id: <random 32+ char string>
octoeverywhere_webhook_id: <random 32+ char string>
```
After changing either webhook ID, update the destination URL in the Stripe and OctoEverywhere dashboards.

**`/config/esphome/secrets.yaml`**
```yaml
wifi_ssid: <network name>
wifi_password: <password>
ap_password: <fallback hotspot password>
kaeser_api_password: <strong password>
kaeser_ota_password: <strong password>
```
After changing ESPHome passwords, flash the device once via USB using the `old_password` migration field (already configured), then remove `old_password` from `kaeser-monitor.yaml`.

---

## GitHub Actions secrets required

| Secret | Value |
|--------|-------|
| `HA_TOKEN` | Long-lived access token from HA profile |
| `HA_URL` | Externally accessible HA URL (e.g. Nabu Casa) |

---

## Initial HA host setup

```bash
cd /config
git init
git remote add origin https://github.com/MakeNashville/home-assistant-config.git
git fetch origin main
git reset --hard origin/main
```

Then create `secrets.yaml` and `esphome/secrets.yaml` with the values above before restarting HA.

---

## Adding a new printer

1. Add it to the printer lists in `automations/printers.yaml` (search for the `bambu_lab_printers` anchor or the `pineapple` Prusa-specific blocks).
2. Add `history_stats` sensors for weekly completed/failed counts in `configuration.yaml`.
3. Add template sensors for Display Name, Object, Last Display Name, Last Object in `configuration.yaml`.
4. Add the printer to the `Roundup` and `Weekly Print Summary` printers lists in `automations/printers.yaml`.
5. Add a `recorder` exclude glob for any high-frequency sensors the integration creates.

## Adding a facilities sensor

Tag the device with the `facilities_pulse` label in HA > Settings > Devices. It will appear automatically in Facilities Pulse messages and the Facilities dashboard temperature grid without any YAML changes.
