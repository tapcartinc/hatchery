#!/bin/bash
# hatch-pair — (re)pair this box to a gateway on demand.
# Usage: docker exec hatch-N hatch-pair "<join-url>"
# Wipes pairing state, stages the new code, and stops the running node process
# so s6 relaunches the service and consumes it. Verify with 'openclaw nodes list'.
set -euo pipefail
# Accept the join URL on stdin (`hatch-pair -`) so it never appears in argv,
# process lists, or shell history. Argv form kept only for manual use.
if [ "${1:-}" = "-" ] || [ $# -eq 0 ]; then
  IFS= read -r URL || true
  URL="${URL%%[[:space:]]*}"
else
  URL="$1"
fi
[ -n "${URL:-}" ] || { echo "usage: hatch-pair - < file-with-join-url" >&2; exit 2; }

# Drop every trace of the previous pairing, or the service takes the
# "already paired" branch and ignores this code.
rm -f /config/.openclaw-initialized
rm -rf /config/.openclaw/node-host

printf '%s' "$URL" > /config/.openclaw-join-url
chown abc:abc /config/.openclaw-join-url

# Stop the running node process. The binaries are named `openclaw` and
# `openclaw-node` — matching on "openclaw node run" never worked and left the
# old process alive, which is what made re-pairing impossible.
pkill -f 'openclaw-node' 2>/dev/null || true
pkill -x 'openclaw' 2>/dev/null || true

echo "[hatch-pair] join code staged; node service will pair momentarily."
