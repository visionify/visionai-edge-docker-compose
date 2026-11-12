#!/usr/bin/env bash
# VisionAI Edge - one-line bootstrap (Motherson hybrid)
#
#   curl -fsSL https://raw.githubusercontent.com/visionify/visionai-edge-docker-compose/motherson-hybrid/get.sh | bash
#
# What it does (no prompts, safe to re-run):
#   1. installs Docker + compose plugin if missing
#   2. installs the NVIDIA container toolkit if missing (NVIDIA driver must already be there)
#      and sets up CDI GPU access for the containers
#   3. downloads the deployment files into ~/visionai-edge
#   4. creates ~/visionai-edge/.env from the template
# Options (environment variables before `bash`):
#   VISIONAI_DIR=/path        install folder            (default ~/visionai-edge)
#   DOCKER_DATA_ROOT=/data/docker   keep Docker images on the large disk (default: Docker's own)
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
if [ -n "${DOCKER_DATA_ROOT:-}" ]; then
  cur="$(dk info -f '{{.DockerRootDir}}' 2>/dev/null || true)"
  if [ "$cur" != "$DOCKER_DATA_ROOT" ]; then
    $SUDO mkdir -p "$DOCKER_DATA_ROOT"
    $SUDO python3 - "$DOCKER_DATA_ROOT" <<'PY'
import json, sys, os
p = "/etc/docker/daemon.json"
cfg = json.load(open(p)) if os.path.exists(p) and os.path.getsize(p) else {}
cfg["data-root"] = sys.argv[1]
json.dump(cfg, open(p, "w"), indent=2)
PY
    $SUDO systemctl restart docker
    echo "docker images now stored under $DOCKER_DATA_ROOT"
  fi
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

# The containers get the GPU through CDI (docker-compose.yml `driver: cdi`). With the legacy
# nvidia runtime hook a `systemctl daemon-reload` (apt upgrades, other installers) drops the GPU
# from running containers; CDI devices survive it. Toolkit 1.18+ ships nvidia-cdi-refresh, which
# regenerates the CDI spec at boot and after driver updates.
if ! systemctl cat nvidia-cdi-refresh.service >/dev/null 2>&1; then
  echo "upgrading the NVIDIA container toolkit (CDI spec refresh needs 1.18 or newer)"
  { $SUDO apt-get update -qq && $SUDO apt-get install -y -qq nvidia-container-toolkit; } || true
fi
if systemctl cat nvidia-cdi-refresh.service >/dev/null 2>&1; then
  $SUDO systemctl enable --now nvidia-cdi-refresh.path >/dev/null 2>&1 || true
  $SUDO systemctl restart nvidia-cdi-refresh.service
else
  # toolkit without the refresh service: static spec, re-run get.sh after every driver update
  $SUDO mkdir -p /etc/cdi && $SUDO nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml >/dev/null
fi
$SUDO nvidia-ctk cdi list 2>/dev/null | grep -q 'nvidia.com/gpu=all' \
  || fail "no CDI device for the GPU. Run: sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml, then re-run this script"
# CDI is on by default from Docker 28; Docker 25-27 need it switched on, older Docker can't do it
dv="$(dk version -f '{{.Server.Version}}' 2>/dev/null | cut -d. -f1)"
case "$dv" in ''|*[!0-9]*) dv=0 ;; esac
[ "$dv" -ge 25 ] || fail "Docker 25 or newer is needed for CDI GPU access (found $(dk --version)). Upgrade: curl -fsSL https://get.docker.com | sudo sh"
if [ "$dv" -lt 28 ]; then
  $SUDO python3 - <<'PY'
import json, os
p = "/etc/docker/daemon.json"
cfg = json.load(open(p)) if os.path.exists(p) and os.path.getsize(p) else {}
cfg.setdefault("features", {})["cdi"] = True
json.dump(cfg, open(p, "w"), indent=2)
PY
  $SUDO systemctl restart docker
  echo "enabled CDI in Docker $dv"
fi
echo "GPU access OK via CDI ($(nvidia-smi --query-gpu=name --format=csv,noheader | head -1))"

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

# Already configured (re-run / update): apply the refreshed files and newest images right away.
if ! grep -q 'REPLACE_WITH' "$DIR/.env"; then
  echo ".env is configured - updating the running deployment"
  cd "$DIR" && exec bash install.sh
fi

cat <<EOF

Done. Two steps remain:

  1. Fill in the values marked  >>> FILL  (Docker Hub token and site token):
       nano $DIR/.env

  2. Start it:
       cd $DIR && bash install.sh

EOF
