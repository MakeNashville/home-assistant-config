# MakeNashville Home Assistant Config

Home Assistant configuration for the [MakeNashville](https://makenashville.org) makerspace.

## Structure

```
.
├── automations.yaml       # All automations (3D printers, facilities monitoring, etc.)
├── configuration.yaml     # Core HA config, recorder, templates, shell commands
├── scripts.yaml           # Scripts
├── scenes.yaml            # Scenes
├── esphome/               # ESPHome device configs
│   └── kaeser-monitor.yaml  # Kaeser air compressor pressure monitor
├── blueprints/            # Automation blueprints
└── git_backup.sh          # Backup script
```

## Deploy

Merging a PR to `main` automatically deploys to the HA instance via GitHub Actions (`.github/workflows/deploy.yml`). Changes to `automations.yaml`, `scripts.yaml`, or `configuration.yaml` trigger a `git pull` on the HA host followed by a config reload.

**`main` is a protected branch — all changes must go through a pull request.** Direct pushes are not allowed.

### Initial HA host setup

```bash
cd /config
git init
git remote add origin https://github.com/MakeNashville/home-assistant-config.git
git fetch origin main
git reset --hard origin/main
```

### GitHub Actions secrets required

| Secret | Value |
|--------|-------|
| `HA_TOKEN` | Long-lived access token from HA profile |
| `HA_URL` | Externally accessible HA URL (e.g. Nabu Casa) |
