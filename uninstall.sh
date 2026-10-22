#!/usr/bin/env bash
# VisionAI Edge - Motherson hybrid UNINSTALL
# Removes everything the install created on this box:
#   containers, the triton_models volume, the visionai-network, all pulled images
#   (inference, models, Triton), the ~/.visionai data folder, the Docker Hub login,
#   and (optionally) this repo folder.
# Does NOT touch Docker itself, the NVIDIA driver, or anything outside this deployment.
#
# Usage:  bash uninstall.sh            # asks for confirmation
#         bash uninstall.sh --yes      # no prompt
#         bash uninstall.sh --yes --purge-repo   # also deletes this folder
set -uo pipefail
cd "$(dirname "$0")"
REPO_DIR="$(pwd)"
COMPOSE="docker compose"
DATA_DIR="$(grep -E '^VISIONAI_DATA_DIR=.' .env 2>/dev/null | cut -d= -f2- || true)"
DATA_DIR="${DATA_DIR:-${HOME}/.visionai}"
YES=0; PURGE_REPO=0
for a in "$@"; do
  case "$a" in
    --yes|-y) YES=1 ;;
    --purge-repo) PURGE_REPO=1 ;;
    *) echo "unknown option: $a"; exit 2 ;;
  esac
done

step() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

echo "This will remove the VisionAI inference deployment from this machine:"
echo "  - containers : visionai-inference, visionai-triton, visionai-models-init, visionai-watchdog"
echo "  - volume     : triton_models (AI models)"
echo "  - network    : visionai-network"
echo "  - images     : visionify/visionai-inference, visionify/visionai-models, nvcr.io/nvidia/tritonserver, docker:27-cli"
echo "  - data       : ${DATA_DIR} (camera configs, local cache, screenshots)"
echo "  - Docker Hub login for user visionify"
[ "$PURGE_REPO" = 1 ] && echo "  - this folder: ${REPO_DIR}"
echo "Nothing is deleted from the Visionify cloud dashboard."
if [ "$YES" != 1 ]; then
  read -r -p "Type DELETE to continue: " ans
  [ "$ans" = "DELETE" ] || { echo "aborted"; exit 1; }
fi

step "1/6 Stopping and removing containers, network and volumes"
if [ -f docker-compose.yml ]; then
  $COMPOSE down --volumes --remove-orphans || true
fi
# belt and braces, in case the compose file is missing or names differ
docker rm -f visionai-inference visionai-triton visionai-models-init visionai-watchdog 2>/dev/null || true
docker volume rm -f triton_models 2>/dev/null || true
docker network rm visionai-network 2>/dev/null || true

step "2/6 Removing images"
imgs=$(docker image ls --format '{{.Repository}}:{{.Tag}}' \
  | grep -E '^(visionify/visionai-inference|visionify/visionai-models|nvcr.io/nvidia/tritonserver|nvidia/cuda|docker:27-cli)' || true)
if [ -n "$imgs" ]; then
  echo "$imgs" | xargs -r docker image rm -f
else
  echo "no deployment images found"
fi
docker image prune -f >/dev/null 2>&1 || true

step "3/6 Removing local data (${DATA_DIR})"
rm -rf "${DATA_DIR}"

step "4/6 Removing .env with credentials"
rm -f "${REPO_DIR}/.env"

step "5/6 Docker Hub logout"
docker logout >/dev/null 2>&1 || true

step "6/6 Verification"
left_c=$(docker ps -a --format '{{.Names}}' | grep -E '^visionai-' || true)
left_v=$(docker volume ls --format '{{.Name}}' | grep -E '^triton_models$' || true)
left_i=$(docker image ls --format '{{.Repository}}' | grep -E 'visionify|tritonserver' || true)
if [ -z "$left_c$left_v$left_i" ] && [ ! -d "${DATA_DIR}" ]; then
  echo "Clean: no VisionAI containers, volumes, images or data remain."
else
  echo "Leftovers (remove manually):"; printf '%s\n' $left_c $left_v $left_i
fi
docker system df

if [ "$PURGE_REPO" = 1 ]; then
  step "Deleting repo folder ${REPO_DIR}"
  cd / && rm -rf "${REPO_DIR}" && echo "deleted"
fi
echo
echo "Uninstall complete. Docker and the NVIDIA driver were left in place."
