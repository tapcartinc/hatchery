FROM lscr.io/linuxserver/webtop:ubuntu-xfce

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential jq ripgrep wget zip unzip htop nano ffmpeg scrot xdotool \
    ca-certificates gnupg \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
  && apt-get install -y nodejs \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN npm install -g @tapcart/tapcart-cli openclaw@2026.8.1

RUN mkdir -p /custom-services.d
COPY openclaw-node.sh /custom-services.d/openclaw-node
RUN chmod +x /custom-services.d/openclaw-node
