# VisionAI Edge-Docker-Compose Setup

This repository contains the Docker Compose configuration for setting up VisionAI services, including Prometheus, Grafana, cAdvisor, Triton Inference Server, and multiple VisionAI API instances.

## Prerequisites

- Docker
- Docker Compose

## Services

### Prometheus

Prometheus is used for monitoring and alerting.

- **Image:** prom/prometheus:latest
- **Ports:** 9090:9090
- **Volumes:** 
  - `prometheus_data:/prometheus`
  - `./prometheus:/etc/prometheus`
- **Command:** 
  - `--config.file=/etc/prometheus/prometheus.yml`
  - `--storage.tsdb.path=/prometheus`
  - `--web.enable-lifecycle`

### Grafana

Grafana is used for visualization of metrics.

- **Image:** grafana/grafana:latest
- **Ports:** 9091:9091
- **Volumes:** 
  - `grafana_data:/var/lib/grafana`
  - `./grafana/datasources:/etc/grafana/provisioning/datasources`
  - `./grafana/dashboards:/etc/grafana/provisioning/dashboards`
- **Environment Variables:**
  - `GF_SECURITY_ADMIN_PASSWORD=secret`
  - `GF_SERVER_HTTP_PORT=9091`
  - `GF_LOG_LEVEL=debug`
- **Depends On:** prometheus

### cAdvisor

cAdvisor provides container resource usage and performance characteristics.

- **Image:** gcr.io/cadvisor/cadvisor
- **Ports:** 9092:8080
- **Volumes:**
  - `/:/rootfs:ro`
  - `/var/run:/var/run:rw`
  - `/sys:/sys:ro`
  - `/var/lib/docker/:/var/lib/docker:ro`

### Triton Inference Server

Triton Inference Server for serving AI models.

- **Image:** nvcr.io/nvidia/tritonserver:23.10-py3
- **Ports:**
  - 8000:8000
  - 8001:8001
  - 8002:8002
- **Volumes:** 
  - `$HOME/.visionai/models-repo:/models`
- **Command:** `tritonserver --model-store=/models`
- **Deploy:**
  - Restart Policy: on-failure
  - Resources:
    - Reservations:
      - Devices:
        - driver: nvidia
        - count: 1
        - capabilities: [gpu]

### VisionAI API

Multiple instances of VisionAI API.

- **Image:** visionify/visionai-api:latest
- **Ports:** 
  - 3002:3002
  - 3003:3003
- **Volumes:**
  - `./.env:/App/.env`
  - `${HOME}/.visionai:/App/.visionai`
- **Environment Variables:**
  - `HOST_PATH=/App/.visionai`
  - `INSTANCE_ID="1"`
- **Depends On:** visionai-triton
- **Command:** `python3 server.py`
- **Deploy:** 
  - Restart Policy: on-failure

### VisionAI Screenshots

Service for taking screenshots.

- **Image:** visionify/visionai-screenshots:latest
- **Build:** .
- **Restart Policy:** unless-stopped

## Networks

- **visionai-network:** bridge

## Volumes

- **prometheus_data**
- **grafana_data**

## How to Run

1. Clone this repository.
   ```bash
   git clone <repository-url>
   cd <repository-directory>
   ```

2. Create `.env` files for each VisionAI API instance and populate them with the necessary environment variables.

3. Start the services.
   ```bash
   docker-compose up -d
   ```

4. Access the services via their respective ports:
   - Prometheus: http://localhost:9090
   - Grafana: http://localhost:9091
   - cAdvisor: http://localhost:9092
   - VisionAI APIs: 
     - http://localhost:3002
     - http://localhost:3003
     - http://localhost:3012
     - http://localhost:3013
     - http://localhost:3014
     - http://localhost:3015
     - http://localhost:3016
     - http://localhost:3017
