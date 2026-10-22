#!/usr/bin/env bash
# VisionAI Edge - one-line bootstrap (Motherson hybrid)
#
#   curl -fsSL https://raw.githubusercontent.com/visionify/visionai-edge-docker-compose/motherson-hybrid/get.sh | bash
#
# What it does (no prompts, safe to re-run):
#   1. installs Docker + compose plugin if missing
#   2. installs the NVIDIA container toolkit if missing (NVIDIA driver must already be there)
#   3. downloads the deployment files into ~/visionai-edge
#   4. creates ~/visionai-edge/.env from the template
# Then:  edit ~/visionai-edge/.env  ->  cd ~/visionai-edge && bash install.sh
set -euo pipefail

step() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
fail() { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

BRANCH="${VISIONAI_BRANCH:-motherson-hybrid}"
REPO="visionify/visionai-edge-docker-compose"
DIR="${VISIONAI_DIR:-$HOME/visionai-edge}"
SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  SUDO="sudo"
  # curl | bash leaves no stdin for sudo; ask for the password once, from the terminal
  if ! sudo -n true 2>/dev/null; then
    echo "sudo password is needed once for package installs:"
    sudo -v </dev/tty || fail "sudo is required"
  fi
fi
dk() { docker "$@" 2>/dev/null || $SUDO docker "$@"; }

step "1/4 Docker"
if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | $SUDO sh
fi
if ! dk compose version >/dev/null 2>&1; then
  $SUDO apt-get install -y docker-compose-plugin
fi
if [ -n "$SUDO" ] && ! id -nG | grep -qw docker; then
  $SUDO usermod -aG docker "$USER"
  echo "added $USER to the docker group (takes effect at next login; install.sh uses sudo until then)"
fi
echo "$(dk --version)"

step "2/4 NVIDIA container toolkit"
command -v nvidia-smi >/dev/null 2>&1 || fail "nvidia-smi not found - install the NVIDIA driver first (sudo ubuntu-drivers install), reboot, then re-run"
if ! (dk info 2>/dev/null | grep -qi 'nvidia'); then
  curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | $SUDO gpg --dearmor --yes -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
  curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
    | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
    | $SUDO tee /etc/apt/sources.list.d/nvidia-container-toolkit.list >/dev/null
  $SUDO apt-get update -qq && $SUDO apt-get install -y -qq nvidia-container-toolkit
  $SUDO nvidia-ctk runtime configure --runtime=docker
  $SUDO systemctl restart docker
fi
echo "nvidia runtime OK ($(nvidia-smi --query-gpu=name --format=csv,noheader | head -1))"

step "3/4 Deployment files -> $DIR"
mkdir -p "$DIR"
curl -fsSL "https://github.com/$REPO/archive/refs/heads/$BRANCH.tar.gz" \
  | tar -xz -C "$DIR" --strip-components=1
echo "downloaded branch $BRANCH"

step "4/4 Configuration"
if [ -f "$DIR/.env" ]; then
  echo "$DIR/.env already exists, keeping it"
else
  cp "$DIR/.env.example" "$DIR/.env"
  echo "created $DIR/.env"
fi

cat <<EOF

Done. Two steps remain:

  1. Fill in the values marked  >>> FILL  (Docker Hub token, dashboard URL, site token, blob string):
       nano $DIR/.env

  2. Start it:
       cd $DIR && bash install.sh

EOF
