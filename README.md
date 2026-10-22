# VisionAI Edge - Motherson Hybrid Installation

**Hybrid model:** the VisionAI dashboard, control-plane and event storage run in Visionify cloud.
The Motherson on-prem GPU server runs only the inference stack:

| Container | Image | Role |
|-----------|-------|------|
| `visionai-models-init` | `visionify/visionai-models` | One-shot job: copies AI models into a Docker volume, then exits |
| `visionai-triton` | `nvcr.io/nvidia/tritonserver:25.09-py3` | NVIDIA Triton model server (starts after models-init) |
| `visionai-inference` | `visionify/visionai-inference` | Reads cameras (RTSP), runs detections, sends events to the cloud dashboard |
| `visionai-watchdog` | `docker:27-cli` | Remote kill switch: removes the deployment when the site token is revoked in the dashboard |

Total install time: ~15 minutes (most of it is image download). Three commands: the curl one-liner, edit `.env`, `bash install.sh`.

---

## 0. Before the call (Visionify side)

- Docker Hub **read-only access token** for user `visionify`, label `motherson-edge-pull` (Docker Hub -> Account settings -> Personal access tokens -> Generate, scope **Read-only**).
- Motherson site created in the cloud dashboard and its **site API token** copied.
- Azure Blob **connection string** for event media.
- Firebase service-account values (if realtime features are enabled for the site).

Hand the IT team a filled `.env` (or dictate the `>>> FILL` lines) and the Docker Hub token over a secure channel. Never paste them into chat/email.

---

## 1. Server requirements (Motherson IT)

| Item | Requirement |
|------|-------------|
| OS | Ubuntu 22.04 / 24.04 LTS, x86_64, user with sudo |
| GPU | NVIDIA (8 GB+ VRAM) with the NVIDIA driver installed (`nvidia-smi` works) |
| RAM / disk | 16 GB RAM, 100 GB free disk |
| Network (outbound) | HTTPS (443) to `github.com`, `hub.docker.com`, `*.docker.io`, `nvcr.io`, the Visionify dashboard URL, `*.blob.core.windows.net`, `*.firebasedatabase.app` |
| Network (inbound, LAN) | RTSP (554) from cameras to this server |

Docker and the NVIDIA container toolkit are installed by the one-liner below if missing.

---

## 2. Install (one command)

```bash
curl -fsSL https://raw.githubusercontent.com/visionify/visionai-edge-docker-compose/motherson-hybrid/get.sh | bash
```

This installs Docker and the NVIDIA container toolkit if needed, downloads the deployment files to `~/visionai-edge`, and creates `~/visionai-edge/.env` from the template. No prompts.

---

## 3. Configure

```bash
nano ~/visionai-edge/.env
```

Fill every line marked `>>> FILL`:

| Variable | Value |
|----------|-------|
| `DOCKERHUB_TOKEN` | Read-only Docker Hub access token provided by Visionify (the only Docker credential; no password) |
| `VISIONAI_API_ENDPOINT` | Cloud dashboard API URL, e.g. `https://app.visionify.ai/api` |
| `VISIONAI_API_TOKEN` | Site API token from the dashboard |
| `EVENTS_AZURE_BLOB_CONNECTION_STRING` | Azure Blob connection string from Visionify |
| `FIREBASE_*` | Firebase values from Visionify (uncomment the lines) |

Everything else can stay at the defaults.

---

## 4. Run

```bash
cd ~/visionai-edge && bash install.sh
```

The installer checks GPU access from Docker, logs in to Docker Hub with the token from `.env`, pulls the images, starts the stack and waits for Triton to be healthy. Re-run it any time to apply `.env` changes or upgrade images.

---

## 5. Verify

```bash
docker compose ps
```

Expected:

```
visionai-models-init   Exited (0)
visionai-triton        Up (healthy)
visionai-inference     Up
```

```bash
curl -s localhost:8000/v2/health/ready && echo "triton ready"
docker compose logs -f visionai-inference   # look for "connected" / scenarios starting
```

Then in the cloud dashboard: the Motherson site shows **Online**, and cameras added in the dashboard start producing events.

---

## Day-2 operations

```bash
C="docker compose"

$C logs -f visionai-inference        # live logs
$C restart visionai-inference        # restart inference only
$C pull && $C up -d                  # upgrade to the newest images
$C down                              # stop everything (models volume is kept)
bash uninstall.sh          # full removal, see "Uninstall" below
docker volume rm triton_models       # force models to be re-copied on next 'up'
```

Logs are rotated automatically (5 x 20 MB per container). The stack restarts on reboot.

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `pull access denied` | Check `DOCKERHUB_TOKEN` in `.env`, then `bash install.sh` again |
| `could not select device driver "nvidia"` | NVIDIA container toolkit not installed / docker not restarted (see step 1) |
| `visionai-models-init` exited with code 1 | Image has no baked models; `docker compose pull visionai-models-init` and `up -d` again |
| Triton stays `starting` > 5 min | `docker logs visionai-triton`, check GPU memory with `nvidia-smi` |
| Inference logs `401` / `403` | Wrong `VISIONAI_API_TOKEN` or `VISIONAI_API_ENDPOINT` in `.env`, then `$C up -d` |
| Cameras show no frames | RTSP reachability from the server: `ffprobe rtsp://user:pass@camera-ip/...` (or `nc -zv camera-ip 554`) |
| Events without images | Outbound HTTPS to `*.blob.core.windows.net` blocked by firewall |

---

## Uninstall (full removal)

To remove the deployment from the server entirely, containers, the models volume, the network, all pulled images, local data in `~/.visionai`, the `.env` and the Docker Hub login:

```bash
cd ~/visionai-edge
bash uninstall.sh                      # asks you to type DELETE
bash uninstall.sh --yes                # no prompt
bash uninstall.sh --yes --purge-repo   # also deletes this folder
```

The script prints a verification at the end ("Clean: no VisionAI containers, volumes, images or data remain"). Docker and the NVIDIA driver are left installed. Nothing is deleted in the cloud dashboard; disable or delete the site there separately, and revoke the Docker Hub access token in Docker Hub.

## Remote removal from the dashboard (no access to the box needed)

The `visionai-watchdog` container checks the site API token against the cloud every 5 minutes
(`GET /api/token-details`). Once the cloud has rejected the token (HTTP 401) continuously for
`DECOMMISSION_AFTER_MINUTES` (default 120), the watchdog runs the same removal as the uninstall
script by itself: containers, `triton_models` volume, images, local data, `.env`, then its own
container and the network. Only the small `docker:27-cli` image (about 80 MB) stays behind.

To trigger it from Visionify's side:

1. Dashboard: Settings, Sites, Motherson site, **regenerate** (or delete) the API token. The old token is rejected immediately.
2. Wait for the grace period. The site goes offline in the dashboard at once; the box cleans itself up at the end of the period.
3. Revoke the Docker Hub token `motherson-edge-pull`.

Safety rules built into the watchdog: only a 401 from the cloud counts, network outages, 5xx and
404 responses neither count nor reset the timer, and a 200 resets it. So an internet outage at the
plant can never trigger a wipe. Rotating the token for any other reason **will** wipe the box after
the grace period; put the new token into `.env` and restart within that window, or set
`DECOMMISSION_ENABLED=0` before rotating.
