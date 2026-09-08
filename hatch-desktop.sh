#!/usr/bin/with-contenv bash
# Hatchery desktop source (TEST).
# Exposes this box's existing XFCE session to the OpenClaw Control UI Desktop
# panel via a loopback-only RFB listener. Gateway dials 127.0.0.1 only.
#
# Requires on the GATEWAY side:
#   gateway.nodes.commands.allow: ["desktop.stream"]
#   then re-approve the widened pairing: openclaw nodes pending / approve <id>
export HOME=/config
DISPLAY_TARGET="${DISPLAY:-:1}"
PWFILE=/config/.vncpass
PORT="${HATCH_DESKTOP_PORT:-5900}"

# Wait for the base image's X server to come up.
for i in $(seq 1 60); do
  if xdpyinfo -display "$DISPLAY_TARGET" >/dev/null 2>&1; then break; fi
  sleep 2
done
if ! xdpyinfo -display "$DISPLAY_TARGET" >/dev/null 2>&1; then
  echo "[hatch-desktop] no X display at $DISPLAY_TARGET after 120s; giving up"
  exec sleep infinity
fi

# Pin the virtual display to a real size; webtop's dummy Xorg shrinks to whatever its own web
# client last reported (1016x80 with none attached), which streams as a sliver.
xrandr -display "$DISPLAY_TARGET" --newmode "1920x1080_60" 173.00 1920 2048 2248 2576 1080 1083 1088 1120 -hsync +vsync 2>/dev/null || true
xrandr -display "$DISPLAY_TARGET" --addmode screen 1920x1080_60 2>/dev/null || true
xrandr -display "$DISPLAY_TARGET" --output screen --mode 1920x1080_60 2>/dev/null || true

# Ephemeral per-boot VNC password, node-local, never leaves the container.
if [ ! -f "$PWFILE" ]; then
  PW="$(head -c 12 /dev/urandom | base64 | tr -d '/+=' | head -c 10)"
  x11vnc -storepasswd "$PW" "$PWFILE" >/dev/null 2>&1
  printf '%s' "$PW" > "$PWFILE.txt"          # node host needs plaintext UTF-8, x11vnc needs -storepasswd format
  chown abc:abc "$PWFILE" "$PWFILE.txt"
  chmod 600 "$PWFILE" "$PWFILE.txt"
fi

# Tell the node host to advertise a desktop source (idempotent).
s6-setuidgid abc env HOME=/config openclaw config set desktop.host.enabled true --strict-json || true
s6-setuidgid abc env HOME=/config openclaw config set desktop.host.port "$PORT" --strict-json || true
s6-setuidgid abc env HOME=/config openclaw config set desktop.host.passwordFile "$PWFILE.txt" || true

# Nudge the node host so it re-declares its surface with desktop.stream.
if [ -d /run/service/custom-svc-openclaw-node ]; then
  s6-svc -r /run/service/custom-svc-openclaw-node 2>/dev/null || true
fi

echo "[hatch-desktop] x11vnc on 127.0.0.1:$PORT attached to $DISPLAY_TARGET"
exec x11vnc -display "$DISPLAY_TARGET" -localhost -rfbport "$PORT" \
  -rfbauth "$PWFILE" -forever -shared -noshm -noxdamage -repeat -q
