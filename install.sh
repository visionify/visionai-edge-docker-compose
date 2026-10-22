#!/usr/bin/env bash
# VisionAI Edge - Motherson hybrid installer (models-init + Triton + inference + watchdog)
# Run after filling .env:   cd ~/visionai-edge && bash install.sh
# Safe to re-run; also the way to apply .env changes or upgrade images.
set -euo pipefail
cd "$(dirname "$0")"

step() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
fail() { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

# docker, with sudo fallback until the user's docker-group membership is active
DOCKER="docker"
if ! docker info >/dev/null 2>&1; then
  sudo -n docker info >/dev/null 2>&1 && DOCKER="sudo docker" || fail "cannot talk to docker. Run: curl -fsSL https://raw.githubusercontent.com/visionify/visionai-edge-docker-compose/motherson-hybrid/get.sh | bash"
fi
COMPOSE="$DOCKER compose"

step "1/6 Configuration (.env)"
[ -f .env ] || { cp .env.example .env; echo "created .env from .env.example"; }
if grep -q 'REPLACE_WITH' .env; then
  echo "These lines in .env still need values:"; grep -n 'REPLACE_WITH' .env
  fail "edit .env (nano .env), then run: bash install.sh"
fi
DATA_DIR="$(grep -E '^VISIONAI_DATA_DIR=.' .env | cut -d= -f2- | tr -d '"\r ' || true)"; DATA_DIR="${DATA_DIR:-${HOME}/.visionai}"
if ! mkdir -p "$DATA_DIR" 2>/dev/null; then
  sudo mkdir -p "$DATA_DIR" && sudo chown "$(id -u):$(id -g)" "$DATA_DIR"
fi
[ -w "$DATA_DIR" ] || fail "data folder $DATA_DIR is not writable by $USER"
echo "data folder: $DATA_DIR"
DOCKERHUB_TOKEN="$(grep -E '^DOCKERHUB_TOKEN=.' .env | cut -d= -f2- | tr -d '"\r ' || true)"
echo ".env OK"

step "2/6 Checking GPU access from Docker"
nvidia-smi >/dev/null 2>&1 || fail "nvidia-smi failed - install the NVIDIA driver first"
$DOCKER run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi >/dev/null 2>&1 \
  || fail "GPU not visible inside docker. Re-run get.sh, or: sudo nvidia-ctk runtime configure --runtime=docker && sudo systemctl restart docker"
echo "GPU visible in containers"

step "3/6 Docker Hub login (access token from .env)"
# Docker Hub access tokens are tied to the visionify account; the token is the only secret.
echo "${DOCKERHUB_TOKEN}" | $DOCKER login -u visionify --password-stdin

step "4/6 Pulling images (models image is large, this can take a while)"
$COMPOSE pull

step "5/6 Starting stack"
# An earlier install under a different compose project name (older files, other folder)
# would clash on the container names: take it down first, models are re-copied on start.
for old in $($DOCKER ps -a --filter name='^visionai-' --format '{{.Label "com.docker.compose.project"}}' | sort -u); do
  if [ -n "$old" ] && [ "$old" != "visionai-edge" ]; then
    echo "removing previous deployment (project $old)"
    $COMPOSE -p "$old" down --volumes --remove-orphans >/dev/null 2>&1 || $DOCKER rm -f $($DOCKER ps -aq --filter name='^visionai-') >/dev/null 2>&1 || true
  fi
done
$COMPOSE up -d

step "6/6 Waiting for Triton + inference to become healthy"
for i in $(seq 1 60); do
  st=$($DOCKER inspect -f '{{.State.Health.Status}}' visionai-triton 2>/dev/null || echo starting)
  [ "$st" = "healthy" ] && break
  printf '   triton: %s (%ss)\r' "$st" $((i*10)); sleep 10
done; echo
$COMPOSE ps
echo
if [ "$($DOCKER inspect -f '{{.State.Health.Status}}' visionai-triton 2>/dev/null)" = "healthy" ]; then
  echo "Triton healthy. Inference connects to the cloud dashboard within ~1 minute; the site should show Online."
  echo "Watchdog armed: regenerating the site token in the dashboard removes this deployment after $(grep -E '^DECOMMISSION_AFTER_MINUTES=' .env | cut -d= -f2 || echo 120) min."
  echo "Logs:   $COMPOSE logs -f visionai-inference"
else
  echo "Triton not healthy yet. Check:   $COMPOSE logs visionai-models-init visionai-triton"
fi
