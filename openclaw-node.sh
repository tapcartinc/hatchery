#!/usr/bin/with-contenv bash
# Hatchery node service. First boot: pair via OPENCLAW_JOIN_URL + enable session hosting.
# Ephemeral by design — no volumes. Destroy = wipe.
export HOME=/config
mkdir -p /config/.npm
chown -R abc:abc /config 2>/dev/null

if [ ! -f /config/.openclaw-initialized ]; then
  if [ -z "${OPENCLAW_JOIN_URL}" ]; then
    echo "[hatchery] OPENCLAW_JOIN_URL not set; node disabled."
    exec sleep infinity
  fi
  s6-setuidgid abc env HOME=/config openclaw config set nodeHost.workerRuns.enabled true --strict-json || true
  s6-setuidgid abc env HOME=/config openclaw config set nodeHost.workerRuns.capacity 1 --strict-json || true
  touch /config/.openclaw-initialized
  chown abc:abc /config/.openclaw-initialized
  echo "[hatchery] first boot: pairing as ${OPENCLAW_NODE_NAME:-unnamed}..."
  exec s6-setuidgid abc env HOME=/config openclaw connect "${OPENCLAW_JOIN_URL}" ${OPENCLAW_NODE_NAME:+--display-name "$OPENCLAW_NODE_NAME"}
fi
echo "[hatchery] starting node host with stored identity..."
exec s6-setuidgid abc env HOME=/config openclaw node run ${OPENCLAW_NODE_NAME:+--display-name "$OPENCLAW_NODE_NAME"}
