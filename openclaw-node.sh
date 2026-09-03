#!/usr/bin/with-contenv bash
# Hatchery node service (v2 — gateway-driven pairing).
# Boots idle. The fleet manager pairs a box on demand with:
#   docker exec hatch-N hatch-pair "<join-url>"
# Retries are safe: hatch-pair resets state and this service (restarted by s6)
# re-pairs with the new code. Ephemeral by design — no volumes.
export HOME=/config
mkdir -p /config/.npm
chown -R abc:abc /config 2>/dev/null

# Already paired once: run the node host with stored identity.
if [ -f /config/.openclaw-initialized ]; then
  echo "[hatchery] starting node host with stored identity..."
  exec s6-setuidgid abc env HOME=/config openclaw node run ${OPENCLAW_NODE_NAME:+--display-name "$OPENCLAW_NODE_NAME"}
fi

# Standalone mode: join URL provided via env at boot.
if [ -n "${OPENCLAW_JOIN_URL:-}" ] && [ ! -f /config/.openclaw-join-url ]; then
  printf '%s' "$OPENCLAW_JOIN_URL" > /config/.openclaw-join-url
  chown abc:abc /config/.openclaw-join-url
fi

# Idle until a join URL exists (dropped by hatch-pair or env above).
echo "[hatchery] waiting for join URL (hatch-pair)..."
while [ ! -f /config/.openclaw-join-url ]; do
  sleep 2
done

s6-setuidgid abc env HOME=/config openclaw config set nodeHost.workerRuns.enabled true --strict-json || true
s6-setuidgid abc env HOME=/config openclaw config set nodeHost.workerRuns.capacity 1 --strict-json || true
touch /config/.openclaw-initialized
chown abc:abc /config/.openclaw-initialized
echo "[hatchery] pairing as ${OPENCLAW_NODE_NAME:-unnamed}..."
exec s6-setuidgid abc env HOME=/config openclaw connect "$(cat /config/.openclaw-join-url)" ${OPENCLAW_NODE_NAME:+--display-name "$OPENCLAW_NODE_NAME"}
