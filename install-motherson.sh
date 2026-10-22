#!/usr/bin/env bash
# VisionAI Edge - Motherson hybrid installer (inference + Triton + models-init only)
# Run from the repo root on the GPU box:   bash install-motherson.sh
set -euo pipefail
cd "$(dirname "$0")"
COMPOSE="docker compose -f docker-compose.motherson.yml"
DOCKERHUB_USER="${DOCKERHUB_USER:-visionify}"

step() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
fail() { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

step "1/6 Checking prerequisites"
command -v docker >/dev/null || fail "docker not installed. Run: curl -fsSL https://get.docker.com | sudo sh"
docker compose version >/dev/null 2>&1 || fail "docker compose plugin missing (apt install docker-compose-plugin)"
docker info >/dev/null 2>&1 || fail "cannot talk to docker daemon. Add user to docker group: sudo usermod -aG docker \$USER && re-login"
nvidia-smi >/dev/null 2>&1 || fail "nvidia-smi failed - install NVIDIA driver first"
docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi >/dev/null 2>&1 \
  || fail "GPU not visible inside docker. Install nvidia-container-toolkit and run: sudo nvidia-ctk runtime configure --runtime=docker && sudo systemctl restart docker"
echo "docker, compose, NVIDIA driver and container toolkit OK"

step "2/6 Docker Hub login (pull-only token provided by Visionify)"
if docker pull -q visionify/visionai-inference:latest >/dev/null 2>&1; then
  echo "already logged in"
else
  if [ -z "${DOCKERHUB_TOKEN:-}" ]; then
    read -r -s -p "Paste the Docker Hub access token for user '${DOCKERHUB_USER}': " DOCKERHUB_TOKEN; echo
  fi
  echo "$DOCKERHUB_TOKEN" | docker login -u "$DOCKERHUB_USER" --password-stdin
fi

step "3/6 Environment file"
if [ ! -f .env ]; then
  cp motherson.env.example .env
  echo "created .env from motherson.env.example"
fi
if grep -q 'REPLACE_WITH' .env; then
  echo "The following lines in .env still need values:"; grep -n 'REPLACE_WITH' .env
  fail "edit .env (nano .env), then re-run this script"
fi
mkdir -p "${HOME}/.visionai"

step "4/6 Pulling images (models image is large, this can take a while)"
$COMPOSE pull

step "5/6 Starting stack"
$COMPOSE up -d

step "6/6 Waiting for Triton + inference to become healthy"
for i in $(seq 1 60); do
  st=$(docker inspect -f '{{.State.Health.Status}}' visionai-triton 2>/dev/null || echo starting)
  [ "$st" = "healthy" ] && break
  printf '   triton: %s (%ss)\r' "$st" $((i*10)); sleep 10
done; echo
$COMPOSE ps
echo
if [ "$(docker inspect -f '{{.State.Health.Status}}' visionai-triton 2>/dev/null)" = "healthy" ]; then
  echo "Triton healthy. Inference should connect to the cloud dashboard within ~1 minute."
  echo "Follow logs with:   $COMPOSE logs -f visionai-inference"
else
  echo "Triton not healthy yet. Check:   $COMPOSE logs visionai-models-init visionai-triton"
fi
