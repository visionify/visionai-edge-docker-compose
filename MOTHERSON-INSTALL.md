# VisionAI Edge - Motherson Hybrid Installation

**Hybrid model:** the VisionAI dashboard, control-plane and event storage run in Visionify cloud.
The Motherson on-prem GPU server runs only the inference stack:

| Container | Image | Role |
|-----------|-------|------|
| `visionai-models-init` | `visionify/visionai-models` | One-shot job: copies AI models into a Docker volume, then exits |
| `visionai-triton` | `nvcr.io/nvidia/tritonserver:25.09-py3` | NVIDIA Triton model server (starts after models-init) |
| `visionai-inference` | `visionify/visionai-inference` | Reads cameras (RTSP), runs detections, sends events to the cloud dashboard |

Total install time: ~15 minutes (most of it is image download).

---

## 0. Before the call (Visionify side)

- Docker Hub **read-only access token** for user `visionify`, label `motherson-edge-pull` (Docker Hub -> Account settings -> Personal access tokens -> Generate, scope **Read-only**).
- Motherson site created in the cloud dashboard and its **site API token** copied.
- Azure Blob **connection string** for event media.
- Firebase service-account values (if realtime features are enabled for the site).

Hand the IT team a filled `.env` (or dictate the `>>> FILL` lines) and the Docker Hub token over a secure channel. Never paste them into chat/email.

---

## 1. Server prerequisites (Motherson IT)

| Item | Requirement |
|------|-------------|
| OS | Ubuntu 22.04 / 24.04 LTS, x86_64 |
| GPU | NVIDIA (8 GB+ VRAM), driver 550+ installed |
| RAM / disk | 16 GB RAM, 100 GB free disk |
| Network (outbound) | HTTPS (443) to `hub.docker.com`, `*.docker.io`, `nvcr.io`, the Visionify dashboard URL, `*.blob.core.windows.net`, `*.firebasedatabase.app` |
| Network (inbound, LAN) | RTSP (554) from cameras to this server; port 3002 from the LAN is optional (local API) |

Quick checks:

```bash
nvidia-smi                                  # driver OK, GPU listed
docker --version && docker compose version  # Docker 24+ and compose v2
docker info | grep -i runtimes              # must list "nvidia"
```

If Docker or the NVIDIA container toolkit is missing:

```bash
# Docker
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER && newgrp docker

# NVIDIA container toolkit
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
  | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
  | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt-get update && sudo apt-get install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker && sudo systemctl restart docker

# Verify GPU inside a container
docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi
```

---

## 2. Get the deployment files

```bash
git clone -b motherson-hybrid https://github.com/visionify/visionai-edge-docker-compose.git
cd visionai-edge-docker-compose
```

(No git on the box? Download the branch ZIP from GitHub and unzip it instead.)

---

## 3. Docker Hub login

```bash
docker login -u visionify
# Password: paste the access token provided by Visionify
```

---

## 4. Configure

```bash
cp motherson.env.example .env
nano .env
```

Fill every line marked `>>> FILL`:

| Variable | Value |
|----------|-------|
| `VISIONAI_API_ENDPOINT` | Cloud dashboard API URL, e.g. `https://app.visionify.ai/api` |
| `VISIONAI_API_TOKEN` | Site API token from the dashboard |
| `EVENTS_AZURE_BLOB_CONNECTION_STRING` | Azure Blob connection string from Visionify |
| `FIREBASE_*` | Firebase values from Visionify (uncomment the lines) |

Everything else can stay at the defaults.

---

## 5. Install

One command does the checks, login, pull and start:

```bash
bash install-motherson.sh
```

Or manually:

```bash
mkdir -p ~/.visionai
docker compose -f docker-compose.motherson.yml pull
docker compose -f docker-compose.motherson.yml up -d
```

---

## 6. Verify

```bash
docker compose -f docker-compose.motherson.yml ps
```

Expected:

```
visionai-models-init   Exited (0)
visionai-triton        Up (healthy)
visionai-inference     Up
```

```bash
curl -s localhost:8000/v2/health/ready && echo "triton ready"
docker compose -f docker-compose.motherson.yml logs -f visionai-inference   # look for "connected" / scenarios starting
```

Then in the cloud dashboard: the Motherson site shows **Online**, and cameras added in the dashboard start producing events.

---

## Day-2 operations

```bash
C="docker compose -f docker-compose.motherson.yml"

$C logs -f visionai-inference        # live logs
$C restart visionai-inference        # restart inference only
$C pull && $C up -d                  # upgrade to the newest images
$C down                              # stop everything (models volume is kept)
docker volume rm triton_models       # force models to be re-copied on next 'up'
```

Logs are rotated automatically (5 x 20 MB per container). The stack restarts on reboot.

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `pull access denied` | `docker login -u visionify` with the access token |
| `could not select device driver "nvidia"` | NVIDIA container toolkit not installed / docker not restarted (see step 1) |
| `visionai-models-init` exited with code 1 | Image has no baked models; `docker compose pull visionai-models-init` and `up -d` again |
| Triton stays `starting` > 5 min | `docker logs visionai-triton`, check GPU memory with `nvidia-smi` |
| Inference logs `401` / `403` | Wrong `VISIONAI_API_TOKEN` or `VISIONAI_API_ENDPOINT` in `.env`, then `$C up -d` |
| Cameras show no frames | RTSP reachability from the server: `ffprobe rtsp://user:pass@camera-ip/...` (or `nc -zv camera-ip 554`) |
| Events without images | Outbound HTTPS to `*.blob.core.windows.net` blocked by firewall |
