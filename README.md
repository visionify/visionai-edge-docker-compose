# VisionAI Edge - Installation Guide

VisionAI runs in two parts. The dashboard runs in the Visionify cloud. The AI inference runs on a GPU server at your site, installed with this guide. The server reads your cameras over RTSP and sends only detection events to the dashboard.

Installation takes about 15 minutes and needs three commands.

## 1. Server requirements

| Item | Requirement |
|------|-------------|
| OS | Ubuntu 22.04 or 24.04 LTS (x86_64), a user with sudo |
| GPU | NVIDIA GPU with 8 GB+ VRAM, NVIDIA driver installed (`nvidia-smi` works) |
| RAM / disk | 16 GB RAM, 100 GB free disk |
| Outbound internet (HTTPS 443) | `github.com`, `hub.docker.com`, `*.docker.io`, `nvcr.io`, `app.visionify.ai`, `*.blob.core.windows.net` |
| Local network | RTSP (port 554) from the cameras to this server |

Docker and the NVIDIA container toolkit are installed automatically in step 2 if missing.

You receive two values from Visionify before installing: a **Docker Hub access token** and a **Site API token**.

## 2. Install

```bash
curl -fsSL https://raw.githubusercontent.com/visionify/visionai-edge-docker-compose/motherson-hybrid/get.sh | bash
```

This installs Docker and the NVIDIA container toolkit if needed and downloads the deployment files to `~/visionai-edge`.

## 3. Configure

```bash
nano ~/visionai-edge/.env
```

Fill in the two lines marked `>>> FILL`:

| Variable | Value |
|----------|-------|
| `DOCKERHUB_TOKEN` | Docker Hub access token from Visionify |
| `VISIONAI_API_TOKEN` | Site API token from Visionify |

Leave everything else at the defaults. Save with `Ctrl+O`, `Enter`, then exit with `Ctrl+X`.

## 4. Start

```bash
cd ~/visionai-edge && bash install.sh
```

The installer checks the GPU, logs in to Docker Hub, downloads the images (several GB, this is the slow part), starts the services and waits until they are healthy.

## 5. Verify

```bash
cd ~/visionai-edge && docker compose ps
```

Expected:

```
visionai-models-init   Exited (0)
visionai-triton        Up (healthy)
visionai-inference     Up
visionai-watchdog      Up
```

In the Visionify dashboard the site shows **Online** within a minute. Cameras are added in the dashboard, not on the server.

## Everyday commands

Run these from `~/visionai-edge`.

```bash
docker compose logs -f visionai-inference    # live logs
docker compose restart visionai-inference    # restart inference
bash install.sh                              # apply .env changes or upgrade to the newest images
docker compose down                          # stop everything (start again with: docker compose up -d)
```

The services start automatically after a reboot.

## Troubleshooting

| Problem | What to do |
|---------|------------|
| `pull access denied` | Check `DOCKERHUB_TOKEN` in `.env`, then run `bash install.sh` again |
| `could not select device driver "nvidia"` | Run the step 2 command again, then `sudo systemctl restart docker` |
| Triton stays `starting` for more than 5 minutes | `docker compose logs visionai-triton` and check free GPU memory with `nvidia-smi` |
| Site stays Offline in the dashboard | Check `VISIONAI_API_TOKEN` in `.env`, then `bash install.sh`. Check the outbound firewall rules in section 1 |
| Cameras show no video | Check the server can reach the camera: `nc -zv <camera-ip> 554` |
| Events have no images | Outbound HTTPS to `*.blob.core.windows.net` is blocked |

## Uninstall

```bash
cd ~/visionai-edge && bash uninstall.sh
```

Removes all VisionAI containers, images, models and local data from the server. Docker and the NVIDIA driver stay installed.
