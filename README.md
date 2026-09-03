# hatchery 🐣

Disposable, self-pairing [OpenClaw](https://openclaw.ai) worker boxes on Docker.

Each box is a full Linux desktop (Ubuntu + XFCE + Chromium + Node 22) that hatches with a fresh
single-use identity, pairs itself to your OpenClaw gateway, does work, and gets culled.
No volumes — destroying a container IS the wipe. Refresh the fleet on a cron and every box
comes back as a brand-new machine with rotated credentials.

## Why

- **Supply-chain isolation** — npm installs and untrusted code run on throwaway boxes, never your real machine
- **Full-send exec** — agents run unrestricted on disposable hardware instead of fighting allowlists
- **Browser + screenshots that just work** — real desktop, real Chromium, viewable in your browser
- **Clean room by construction** — nightly refresh = fresh filesystem + fresh identity, automatically

## Use

```bash
./hatchery.sh up        # mint join codes, generate compose, hatch the fleet
./hatchery.sh down      # destroy fleet = full wipe + deregister nodes
./hatchery.sh refresh   # down + up with fresh identities (cron this)
./hatchery.sh status    # container + node status
HATCH_COUNT=10 ./hatchery.sh up   # scale
```

Nodes register as `hatch-1`, `hatch-2`, ... Desktop viewers at `localhost:3002`, `3003`, ...

## Build the image

```bash
docker buildx build -t hatchery:1 .
```

Customize the Dockerfile with whatever CLIs your agents need — it's a normal image.

## Requirements

- Docker Desktop (Apple Silicon or x86)
- An OpenClaw gateway reachable from the containers (Tailscale works great)
- `openclaw` CLI on the host that runs `hatchery.sh` (it mints the join codes)

## How pairing works

`hatchery.sh up` mints one single-use join code per box via `openclaw devices join-code`
and passes it as an env var. On first boot each box runs `openclaw connect`, generates its
own device identity, and enables worker session hosting. Codes expire in minutes and are
worthless after use. `down` removes the node entries from the gateway, so a refresh is a
full credential rotation.

MIT
