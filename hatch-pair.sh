#!/bin/bash
# hatch-pair — (re)pair this box to a gateway on demand.
# Usage: docker exec hatch-N hatch-pair "<join-url>"
# Resets pairing state and hands the new code to the node service; s6 restarts
# the service, which consumes the code. Gateway verifies via 'openclaw nodes list'.
set -euo pipefail
URL="${1:?usage: hatch-pair <join-url>}"
rm -f /config/.openclaw-initialized
printf '%s' "$URL" > /config/.openclaw-join-url
chown abc:abc /config/.openclaw-join-url
# nudge the service: kill any running node/connect process so s6 relaunches with fresh state
pkill -f 'openclaw node run' 2>/dev/null || true
pkill -f 'openclaw connect' 2>/dev/null || true
echo "[hatch-pair] join code staged; node service will pair momentarily."
