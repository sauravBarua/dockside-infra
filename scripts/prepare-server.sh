#!/usr/bin/env bash
# Prepares an Ubuntu server for Dockside. Safe to run again.
# Usage: bash scripts/prepare-server.sh <dockerhub-username>
set -euo pipefail

DOCKERHUB_USERNAME="${1:-}"
if [ -z "$DOCKERHUB_USERNAME" ]; then
  echo "Usage: bash scripts/prepare-server.sh <dockerhub-username>"
  exit 1
fi

if [ "$(id -u)" -eq 0 ]; then
  echo "Run as a normal user with sudo, not as root."
  exit 1
fi

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$REPO_DIR/.env"
APT="sudo DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get"

# Only on the first run: later runs find our own containers on these ports.
if [ ! -f "$ENV_FILE" ]; then
  for port in 3000 5000; do
    if ss -ltn "sport = :$port" | grep -q LISTEN; then
      echo "Port $port is already in use. Free it or choose other host ports in docker-compose.prod.yaml and nginx/dockside.conf."
      exit 1
    fi
  done
fi

echo "==> Installing packages"
$APT update
$APT install -y nginx ca-certificates curl openssl

if ! command -v docker >/dev/null 2>&1; then
  echo "==> Installing Docker"
  curl -fsSL https://get.docker.com | sudo env DEBIAN_FRONTEND=noninteractive sh
fi
sudo usermod -aG docker "$USER"

echo "==> Installing the Nginx site"
sudo cp "$REPO_DIR/nginx/dockside.conf" /etc/nginx/sites-available/dockside
sudo ln -sf /etc/nginx/sites-available/dockside /etc/nginx/sites-enabled/dockside
if [ -L /etc/nginx/sites-enabled/default ]; then
  sudo rm /etc/nginx/sites-enabled/default
fi
sudo nginx -t
sudo systemctl enable --now nginx
sudo systemctl reload nginx

if [ -f "$ENV_FILE" ]; then
  echo "==> $ENV_FILE already exists, leaving it unchanged"
else
  echo "==> Creating $ENV_FILE with generated secrets"
  (
    umask 077
    cat > "$ENV_FILE" <<EOF
REGISTRY=docker.io
IMAGE_NAMESPACE=$DOCKERHUB_USERNAME
API_TAG=latest
WEB_TAG=latest
POSTGRES_PASSWORD=$(openssl rand -hex 24)
JWT_ACCESS_SECRET=$(openssl rand -hex 32)
EOF
  )
fi

echo "==> Server is ready"