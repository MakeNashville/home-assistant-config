#!/bin/bash
# Local validation and preview for the MakeNashville HA config.
#
# Usage:
#   ./validate.sh              Validate config (same as CI)
#   ./validate.sh --preview    Boot a local HA instance with mock entity data
#
# Requires: Docker

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONTAINER_NAME="ha-preview-$$"
TMPDIR=""
MODE="validate"
PORT=8123

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

usage() {
  echo "Usage: $(basename "$0") [--preview] [--port PORT]"
  echo ""
  echo "  (default)    Validate HA config via Docker (same check as CI)"
  echo "  --preview    Boot a local HA instance with mock entity states"
  echo "  --port PORT  Port for preview mode (default: 8123)"
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --preview)  MODE="preview"; shift ;;
    --port)     PORT="$2"; shift 2 ;;
    -h|--help)  usage; exit 0 ;;
    *)          echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

# ── Helpers ───────────────────────────────────────────────────────────

check_docker() {
  if ! command -v docker &>/dev/null; then
    echo -e "${RED}Docker is required but not installed.${NC}"
    exit 1
  fi
  if ! docker info &>/dev/null 2>&1; then
    echo -e "${RED}Docker is not running.${NC}"
    exit 1
  fi
}

create_secrets() {
  local dir="$1"
  cat > "$dir/secrets.yaml" <<'SECRETS'
slack_bot_token_header: "Bearer xoxb-dummy"
eventbrite_token_header: "Bearer dummy-token"
eventbrite_webhook_id: "dummy-webhook-id"
stripe_webhook_id: "dummy-stripe-webhook"
octoeverywhere_webhook_id: "dummy-octoeverywhere-webhook"
slack_cancel_print_webhook_id: "dummy-cancel-webhook"
eventbrite_form_webhook_id: "dummy-form-webhook"
SECRETS
}

# Copy config files to a temp directory (avoids touching the repo)
prepare_config() {
  TMPDIR=$(mktemp -d)
  local dest="$TMPDIR/config"
  mkdir -p "$dest"

  # Copy YAML config, scripts, dashboards, automations, themes, esphome
  for item in *.yaml automations dashboards themes esphome; do
    [ -e "$SCRIPT_DIR/$item" ] && cp -r "$SCRIPT_DIR/$item" "$dest/" 2>/dev/null || true
  done

  # Remove any real secrets that may have been copied
  rm -f "$dest/secrets.yaml" "$dest/esphome/secrets.yaml"

  create_secrets "$dest"
  mkdir -p "$dest/www/snapshots"

  echo "$dest"
}

cleanup() {
  if [ -n "$TMPDIR" ] && [ -d "$TMPDIR" ]; then
    rm -rf "$TMPDIR"
  fi
}

cleanup_preview() {
  echo ""
  echo "Stopping Home Assistant..."
  docker stop "$CONTAINER_NAME" 2>/dev/null || true
  docker rm "$CONTAINER_NAME" 2>/dev/null || true
  cleanup
}

# ── Validate mode ─────────────────────────────────────────────────────

run_validate() {
  local config_dir
  config_dir=$(prepare_config)
  trap cleanup EXIT

  echo "Running Home Assistant config check..."
  echo ""

  local output
  output=$(docker run --rm \
    -v "$config_dir:/config" \
    homeassistant/home-assistant:stable \
    python -m homeassistant --script check_config -c /config 2>&1) || true

  echo "$output"
  echo ""

  # If check_config never started, Docker itself failed
  if [ -z "$output" ] || ! grep -q "Testing configuration" <<< "$output"; then
    echo -e "${RED}Docker failed to run. Is the HA image available?${NC}"
    exit 1
  fi

  if grep -qE "(Failed config|Incorrect config)" <<< "$output"; then
    echo -e "${RED}Config check FAILED${NC}"
    exit 1
  else
    echo -e "${GREEN}Config check PASSED${NC}"
  fi
}

# ── Preview mode ──────────────────────────────────────────────────────

run_preview() {
  local config_dir
  config_dir=$(prepare_config)
  trap cleanup_preview EXIT INT TERM

  # Check port availability
  if curl -sf "http://localhost:$PORT" > /dev/null 2>&1; then
    echo -e "${RED}Port $PORT is already in use. Use --port to pick another.${NC}"
    exit 1
  fi

  echo "Starting Home Assistant on port $PORT..."
  docker run -d --name "$CONTAINER_NAME" \
    -v "$config_dir:/config" \
    -p "127.0.0.1:$PORT:8123" \
    homeassistant/home-assistant:stable > /dev/null

  # Wait for HA to accept connections
  local max_wait=180
  local waited=0
  printf "Waiting for Home Assistant to start"
  until curl -sf "http://localhost:$PORT/" > /dev/null 2>&1; do
    printf "."
    sleep 3
    waited=$((waited + 3))
    if [ $waited -ge $max_wait ]; then
      echo ""
      echo -e "${RED}Timed out after ${max_wait}s. Check: docker logs $CONTAINER_NAME${NC}"
      exit 1
    fi
  done
  echo " ready!"

  # Complete onboarding via API so we can inject states
  echo "Setting up preview user..."

  # Wait specifically for onboarding endpoint
  local onboard_ready=false
  for _ in $(seq 1 20); do
    if curl -sf "http://localhost:$PORT/api/onboarding" > /dev/null 2>&1; then
      onboard_ready=true
      break
    fi
    sleep 2
  done

  if [ "$onboard_ready" = false ]; then
    echo -e "${YELLOW}Could not reach onboarding API — you may need to complete setup in the browser.${NC}"
    echo -e "Open http://localhost:$PORT and create an account manually."
  else
    # Create user
    local auth_response
    auth_response=$(curl -sf -X POST \
      -H "Content-Type: application/json" \
      -d "{\"client_id\": \"http://localhost:$PORT/\", \"name\": \"Preview\", \"username\": \"preview\", \"password\": \"preview\", \"language\": \"en\"}" \
      "http://localhost:$PORT/api/onboarding/users" 2>&1) || true

    local auth_code
    auth_code=$(echo "$auth_response" | jq -r '.auth_code // empty' 2>/dev/null)

    if [ -z "$auth_code" ]; then
      echo -e "${YELLOW}Onboarding may already be complete or failed. Try logging in manually.${NC}"
    else
      # Exchange auth code for access token
      local token_response
      token_response=$(curl -sf -X POST \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "grant_type=authorization_code&code=$auth_code&client_id=http://localhost:$PORT/" \
        "http://localhost:$PORT/auth/token" 2>&1) || true

      local access_token
      access_token=$(echo "$token_response" | jq -r '.access_token // empty' 2>/dev/null)

      if [ -n "$access_token" ]; then
        # Finish remaining onboarding steps
        curl -sf -X POST \
          -H "Authorization: Bearer $access_token" \
          -H "Content-Type: application/json" \
          -d '{}' \
          "http://localhost:$PORT/api/onboarding/core_config" > /dev/null 2>&1 || true

        curl -sf -X POST \
          -H "Authorization: Bearer $access_token" \
          -H "Content-Type: application/json" \
          -d '{}' \
          "http://localhost:$PORT/api/onboarding/analytics" > /dev/null 2>&1 || true

        curl -sf -X POST \
          -H "Authorization: Bearer $access_token" \
          -H "Content-Type: application/json" \
          -d "{\"client_id\": \"http://localhost:$PORT/\", \"redirect_uri\": \"http://localhost:$PORT/\"}" \
          "http://localhost:$PORT/api/onboarding/integration" > /dev/null 2>&1 || true

        echo -e "${GREEN}Preview user created (preview / preview)${NC}"

        # Inject mock entity states from snapshots
        inject_states "$access_token"
      else
        echo -e "${YELLOW}Could not get access token. Complete setup in the browser.${NC}"
      fi
    fi
  fi

  echo ""
  echo -e "${GREEN}Home Assistant is running!${NC}"
  echo "  URL:    http://localhost:$PORT"
  echo "  Login:  preview / preview"
  echo ""
  echo "Press Ctrl+C to stop."
  echo ""

  # Follow container logs until stopped
  docker logs -f "$CONTAINER_NAME" 2>&1 || true
}

inject_states() {
  local token="$1"
  local snapshots="$SCRIPT_DIR/entity_snapshots.json"

  if [ ! -f "$snapshots" ]; then
    echo -e "${YELLOW}No entity_snapshots.json — dashboards will show 'entity not available'${NC}"
    return
  fi

  local total
  total=$(jq 'length' "$snapshots")

  if [ "$total" -eq 0 ]; then
    echo -e "${YELLOW}entity_snapshots.json is empty — run write_entity_list.sh on the HA instance first${NC}"
    return
  fi

  echo "Injecting $total mock entity states..."
  local injected=0
  local failed=0

  # Process each entity from snapshots
  local entity_ids
  entity_ids=$(jq -r 'keys[]' "$snapshots")

  for entity_id in $entity_ids; do
    local payload
    payload=$(jq --arg id "$entity_id" \
      '{state: .[$id].state, attributes: .[$id].attributes}' "$snapshots")

    if curl -sf -X POST \
      -H "Authorization: Bearer $token" \
      -H "Content-Type: application/json" \
      -d "$payload" \
      "http://localhost:$PORT/api/states/$entity_id" > /dev/null 2>&1; then
      injected=$((injected + 1))
    else
      failed=$((failed + 1))
    fi
  done

  echo -e "${GREEN}Injected $injected entity states${NC}"
  if [ "$failed" -gt 0 ]; then
    echo -e "${YELLOW}$failed entities could not be injected${NC}"
  fi
}

# ── Main ──────────────────────────────────────────────────────────────

check_docker

case "$MODE" in
  validate) run_validate ;;
  preview)  run_preview ;;
esac
