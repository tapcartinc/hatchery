# syntax=docker/dockerfile:1
FROM lscr.io/linuxserver/webtop:ubuntu-xfce

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential jq ripgrep wget zip unzip htop nano ffmpeg scrot xdotool \
    ca-certificates gnupg git \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
  && apt-get install -y nodejs \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN npm install -g @tapcart/tapcart-cli openclaw@2026.9.1

# --- Agent toolbox -----------------------------------------------------------
# Shell/search/data: fd, bat, tree, sqlite3, tmux, shellcheck, yq, poppler (pdftotext)
# Python: python3 + pip + venv, uv
# Node: pnpm, yarn, typescript, tsx (plain npm -g so every user sees them; corepack caches per-user)
# Browser: Playwright CLI + Chromium (arm64-safe) and agent-browser (Vercel) which
#          auto-detects the Playwright Chromium via PLAYWRIGHT_BROWSERS_PATH.
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip python3-venv \
    fd-find bat tree sqlite3 tmux shellcheck git-lfs poppler-utils file less \
  && ln -sf /usr/bin/fdfind /usr/local/bin/fd && ln -sf /usr/bin/batcat /usr/local/bin/bat \
  && git lfs install --system \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin UV_NO_MODIFY_PATH=1 sh \
  && curl -fsSL "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_$(dpkg --print-architecture)" -o /usr/local/bin/yq \
  && chmod 755 /usr/local/bin/yq /usr/local/bin/uv /usr/local/bin/uvx

RUN npm install -g pnpm yarn typescript tsx agent-browser playwright

ENV PLAYWRIGHT_BROWSERS_PATH=/opt/pw-browsers
RUN playwright install --with-deps chromium \
  && chmod -R a+rX /opt/pw-browsers \
  && printf 'PLAYWRIGHT_BROWSERS_PATH=/opt/pw-browsers\n' >> /etc/environment \
  && printf 'export PLAYWRIGHT_BROWSERS_PATH=/opt/pw-browsers\n' > /etc/profile.d/pw-browsers.sh \
  && apt-get clean && rm -rf /var/lib/apt/lists/*
# -----------------------------------------------------------------------------

# GitHub CLI (official apt repo)
RUN mkdir -p -m 755 /etc/apt/keyrings \
  && wget -qO /etc/apt/keyrings/githubcli-archive-keyring.gpg https://cli.github.com/packages/githubcli-archive-keyring.gpg \
  && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list \
  && apt-get update && apt-get install -y --no-install-recommends gh \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# Baked GitHub auth. Tokens come from ./.env (gitignored, chmod 600) as
# HATCH_GH_TOKEN (brin-tapcart) and HATCH_SLINK_GH_TOKEN (slink-ai) via a BuildKit secret, so it is never in git, the Dockerfile,
# or `docker history` — only in this image layer, on this host.
#   docker build --secret id=hatch_env,src=.env -t hatchery:1 .
# gh config lives in /etc/gh (not /config) so nothing at runtime shadows it.
ENV GH_CONFIG_DIR=/etc/gh
RUN --mount=type=secret,id=hatch_env,required=true \
  set -e; . /run/secrets/hatch_env; \
  [ -n "${HATCH_GH_TOKEN:-}" ] || { echo "HATCH_GH_TOKEN missing from .env" >&2; exit 1; }; \
  mkdir -p /etc/gh; \
  printf '%s' "$HATCH_GH_TOKEN" | gh auth login --with-token; \
  chmod 755 /etc/gh; chmod 644 /etc/gh/*; \
  login="$(gh api user --jq .login)"; uid="$(gh api user --jq .id)"; \
  git config --system credential.helper '!/usr/bin/gh auth git-credential'; \
  git config --system user.name "$login"; \
  git config --system user.email "${uid}+${login}@users.noreply.github.com"; \
  gh auth status

# Second GitHub identity: slink-ai (PR reviewer bot). Separate config dir so it can
# never leak into git pushes; reach it only through the `gh-slink` wrapper.
# hosts.yml is written directly: the PAT lacks read:org, which `gh auth login`
# demands but the pulls/reviews API does not.
RUN --mount=type=secret,id=hatch_env,required=true \
  set -e; . /run/secrets/hatch_env; \
  [ -n "${HATCH_SLINK_GH_TOKEN:-}" ] || { echo "HATCH_SLINK_GH_TOKEN missing from .env" >&2; exit 1; }; \
  mkdir -p /etc/gh-slink; \
  printf 'github.com:\n    user: slink-ai\n    oauth_token: %s\n    git_protocol: https\n' "$HATCH_SLINK_GH_TOKEN" > /etc/gh-slink/hosts.yml; \
  printf '#!/bin/sh\n# gh as slink-ai (PR review bot). Use ONLY for submitting reviews.\nGH_CONFIG_DIR=/etc/gh-slink exec /usr/bin/gh "$@"\n' > /usr/local/bin/gh-slink; \
  chmod 755 /usr/local/bin/gh-slink; \
  gh-slink auth status; \
  chmod 755 /etc/gh-slink; chmod 644 /etc/gh-slink/*

# Tapcart CLI credentials. The CLI authenticates with the READ-ONLY token, which it
# reads from TAPCART_API_KEY in the environment (openclaw-node.sh exports it), so the
# box is preconnected to `tapcart` out of the box. The separate write/admin key is
# kept alongside it for API calls that need it. Same BuildKit-secret path as the gh
# tokens: never in git or image history.
RUN --mount=type=secret,id=hatch_env,required=true \
  set -e; . /run/secrets/hatch_env; \
  [ -n "${HATCH_TAPCART_CLI_TOKEN:-}" ] || { echo "HATCH_TAPCART_CLI_TOKEN missing from .env" >&2; exit 1; }; \
  mkdir -p /etc/tapcart; \
  printf '%s' "$HATCH_TAPCART_CLI_TOKEN" > /etc/tapcart/api-key; \
  printf '%s' "${HATCH_TAPCART_API_KEY:-}" > /etc/tapcart/admin-key; \
  chown root:abc /etc/tapcart/api-key /etc/tapcart/admin-key; \
  chmod 640 /etc/tapcart/api-key /etc/tapcart/admin-key; chmod 755 /etc/tapcart

RUN mkdir -p /custom-services.d
COPY openclaw-node.sh /custom-services.d/openclaw-node
COPY hatch-pair.sh /usr/local/bin/hatch-pair
RUN chmod +x /custom-services.d/openclaw-node /usr/local/bin/hatch-pair
