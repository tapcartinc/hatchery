#!/usr/bin/with-contenv bash
# Hatchery node service (v3 — gateway-driven pairing, fail-safe).
# The fleet manager pairs a box on demand with:
#   docker exec hatch-N hatch-pair "<join-url>"
# Ephemeral by design — no volumes.
#
# v3 fixes the wedge that left boxes unpairable: pairing state is now judged by
# real evidence (/config/.openclaw/node-host, written only by a successful
# `openclaw connect`) instead of a marker file that was touched BEFORE the
# connect attempt. A failed pair now falls back to waiting for a fresh code
# instead of looping `node run` against a nonexistent local gateway.
export HOME=/config
mkdir -p /config/.npm /config/work /config/out
chown -R abc:abc /config 2>/dev/null

# Shared core repo (skills + scripts the workers run). Boxes are ephemeral, so
# clone fresh on every boot; gh credentials are baked into the image.
CORE=/config/.openclaw/tapcart-openclaw-core
if [ ! -d "$CORE/.git" ]; then
  echo "[hatchery] cloning tapcart-openclaw-core..."
  s6-setuidgid abc env HOME=/config git clone -q --depth 1 https://github.com/tapcartinc/tapcart-openclaw-core "$CORE" \
    || echo "[hatchery] WARN: core repo clone failed; workers will clone on demand"
fi

PAIRED_DIR=/config/.openclaw/node-host
JOIN_FILE=/config/.openclaw-join-url

# Really paired: run the node host with the stored identity.
if [ -d "$PAIRED_DIR" ]; then
  echo "[hatchery] starting node host with stored identity..."
  exec s6-setuidgid abc env HOME=/config TAPCART_API_KEY="$(cat /etc/tapcart/api-key 2>/dev/null || true)" TAPCART_ADMIN_KEY="$(cat /etc/tapcart/admin-key 2>/dev/null || true)" openclaw node run ${OPENCLAW_NODE_NAME:+--display-name "$OPENCLAW_NODE_NAME"}
fi

# Not paired. Clear any legacy marker from a half-finished attempt so it can
# never route us into the stored-identity branch above.
rm -f /config/.openclaw-initialized

# Standalone mode: join URL provided via env at boot.
if [ -n "${OPENCLAW_JOIN_URL:-}" ] && [ ! -f "$JOIN_FILE" ]; then
  printf '%s' "$OPENCLAW_JOIN_URL" > "$JOIN_FILE"
  chown abc:abc "$JOIN_FILE"
fi

echo "[hatchery] waiting for join URL (hatch-pair)..."
while [ ! -f "$JOIN_FILE" ]; do
  sleep 2
done

s6-setuidgid abc env HOME=/config openclaw config set nodeHost.workerRuns.enabled true --strict-json || true
s6-setuidgid abc env HOME=/config openclaw config set nodeHost.workerRuns.capacity 1 --strict-json || true

# Consume the code: read it, then delete it. If this connect fails, s6 restarts
# us with no code staged and we wait for a fresh one — a retry now works.
JOIN_URL="$(cat "$JOIN_FILE")"
rm -f "$JOIN_FILE"
echo "[hatchery] pairing as ${OPENCLAW_NODE_NAME:-unnamed}..."
exec s6-setuidgid abc env HOME=/config TAPCART_API_KEY="$(cat /etc/tapcart/api-key 2>/dev/null || true)" TAPCART_ADMIN_KEY="$(cat /etc/tapcart/admin-key 2>/dev/null || true)" openclaw connect "$JOIN_URL" ${OPENCLAW_NODE_NAME:+--display-name "$OPENCLAW_NODE_NAME"}
