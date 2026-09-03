#!/bin/bash
# hatchery — disposable OpenClaw worker fleet
#   ./hatchery.sh up | down | refresh | status
#   Scale: HATCH_COUNT=10 ./hatchery.sh up
set -euo pipefail

HATCH_COUNT="${HATCH_COUNT:-1}"
IMAGE="hatchery:1"
BASE_PORT=3002
MEM_LIMIT="2500m"
DIR="$(cd "$(dirname "$0")" && pwd)"
DOCKER="$HOME/.docker/bin/docker"
COMPOSE_FILE="$DIR/docker-compose.yml"

gen_compose() {
  {
    echo "services:"
    for i in $(seq 1 "$HATCH_COUNT"); do
      port=$((BASE_PORT + i - 1))
      cat <<EOF
  hatch-$i:
    image: $IMAGE
    container_name: hatch-$i
    hostname: hatch-$i
    shm_size: 1g
    mem_limit: $MEM_LIMIT
    ports:
      - "$port:3000"
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=America/Los_Angeles
      - OPENCLAW_JOIN_URL=\${HATCH${i}_JOIN_URL:-}
      - OPENCLAW_NODE_NAME=hatch-$i
    restart: unless-stopped
EOF
    done
  } > "$COMPOSE_FILE"
}

mint_codes() {
  : > "$DIR/.env"
  for i in $(seq 1 "$HATCH_COUNT"); do
    url=""
    for attempt in 1 2 3 4 5; do
      url=$(openclaw devices join-code 2>/dev/null | head -1) && [ -n "$url" ] && break
      echo "join-code mint failed (attempt $attempt), retrying in 5s..." >&2
      sleep 5
    done
    if [ -z "$url" ]; then echo "FATAL: could not mint join code for hatch-$i" >&2; exit 1; fi
    echo "HATCH${i}_JOIN_URL=$url" >> "$DIR/.env"
  done
  chmod 600 "$DIR/.env"
}

clean_nodes() {
  for i in $(seq 1 "$HATCH_COUNT"); do
    openclaw nodes remove --node "hatch-$i" 2>/dev/null || true
  done
}

case "${1:-}" in
  up)
    gen_compose
    mint_codes
    "$DOCKER" compose -f "$COMPOSE_FILE" up -d
    echo "hatchery of $HATCH_COUNT booting — boxes self-pair in ~20s"
    ;;
  down)
    "$DOCKER" compose -f "$COMPOSE_FILE" down 2>/dev/null || true
    clean_nodes
    echo "hatchery destroyed + node entries cleaned (wipe complete)"
    ;;
  refresh)
    "$0" down
    sleep 2
    "$0" up
    ;;
  status)
    "$DOCKER" ps --filter name=hatch- --format '{{.Names}}: {{.Status}}'
    openclaw nodes list
    ;;
  *)
    echo "usage: $0 up|down|refresh|status   (HATCH_COUNT=$HATCH_COUNT)"
    ;;
esac