#!/bin/bash
# hatchery — disposable OpenClaw worker fleet
#   ./hatchery.sh up | down | refresh | status
#   Scale:  HATCH_COUNT=10 ./hatchery.sh up
#   Waves:  WAVE_SIZE=3 (default) boxes boot per wave to avoid cold-boot storms
set -euo pipefail

HATCH_COUNT="${HATCH_COUNT:-6}"
WAVE_SIZE="${WAVE_SIZE:-3}"
WAVE_SETTLE="${WAVE_SETTLE:-45}"   # seconds to let each wave boot + pair
IMAGE="hatchery:1"
BASE_PORT=3002
MEM_LIMIT="2500m"
DIR="$(cd "$(dirname "$0")" && pwd)"
DOCKER="$HOME/.docker/bin/docker"
COMPOSE_FILE="$DIR/docker-compose.yml"

# join codes are minted via the openclaw CLI. On a machine that is not the
# gateway (e.g. a worker Mac mini), pre-mint codes from the gateway and write
# them to .env as HATCH<n>_JOIN_URL before running up (skip minting with
# SKIP_MINT=1 ./hatchery.sh up).

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
    restart: on-failure:3
EOF
    done
  } > "$COMPOSE_FILE"
}

mint_code() {
  # mint one join code with retries (gateway can be briefly busy)
  local url=""
  for attempt in 1 2 3 4 5; do
    url=$(openclaw devices join-code 2>/dev/null | head -1) && [ -n "$url" ] && break
    echo "join-code mint failed (attempt $attempt), retrying in 5s..." >&2
    sleep 5
  done
  [ -n "$url" ] || { echo "FATAL: could not mint join code" >&2; exit 1; }
  echo "$url"
}

clean_nodes() {
  for i in $(seq 1 "$HATCH_COUNT"); do
    openclaw nodes remove --node "hatch-$i" 2>/dev/null || true
  done
}

case "${1:-}" in
  up)
    gen_compose
    [ -f "$DIR/.env" ] || : > "$DIR/.env"
    # hatch in waves: mint each wave's codes right before boot so they can't expire
    i=1
    while [ "$i" -le "$HATCH_COUNT" ]; do
      wave=()
      for j in $(seq "$i" $(( i + WAVE_SIZE - 1 ))); do
        [ "$j" -le "$HATCH_COUNT" ] || break
        if [ "${SKIP_MINT:-0}" != "1" ]; then
          url=$(mint_code)
          # replace or append this box's env line
          grep -v "^HATCH${j}_JOIN_URL=" "$DIR/.env" > "$DIR/.env.tmp" 2>/dev/null || true
          mv "$DIR/.env.tmp" "$DIR/.env"
          echo "HATCH${j}_JOIN_URL=$url" >> "$DIR/.env"
        fi
        wave+=("hatch-$j")
      done
      chmod 600 "$DIR/.env"
      echo "hatching wave: ${wave[*]}"
      "$DOCKER" compose -f "$COMPOSE_FILE" up -d "${wave[@]}"
      i=$(( i + WAVE_SIZE ))
      if [ "$i" -le "$HATCH_COUNT" ]; then
        echo "settling ${WAVE_SETTLE}s before next wave..."
        sleep "$WAVE_SETTLE"
      fi
    done
    echo "hatchery of $HATCH_COUNT hatched in waves of $WAVE_SIZE"
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
    echo "usage: $0 up|down|refresh|status   (HATCH_COUNT=$HATCH_COUNT WAVE_SIZE=$WAVE_SIZE)"
    ;;
esac