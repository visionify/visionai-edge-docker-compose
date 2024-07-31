
---

# VisionAI Edge Docker Compose Setup

This repository contains the Docker Compose configuration for VisionAI services, including Prometheus, Grafana, cAdvisor, Triton Inference Server, and multiple VisionAI API instances.

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/)
- [Docker Compose](https://docs.docker.com/compose/install/)

## How to Run

1. **Clone the Repository:**
   ```bash
   git clone https://github.com/visionify/visionai-edge-docker-compose.git
   cd visionai-edge-docker-compose
   ```

2. **Create `.env` Files:**
   Create and configure environment files (`.env`, `.env2`, etc.) for each VisionAI API instance with the required environment variables.

3. **Start the Services:**
   ```bash
   docker-compose up -d
   ```

4. **Access the Services:**
   - **Prometheus:** [http://localhost:9090](http://localhost:9090)
   - **Grafana:** [http://localhost:9091](http://localhost:9091)
   - **cAdvisor:** [http://localhost:9092](http://localhost:9092)
   - **VisionAI APIs:**
     - [http://localhost:3002](http://localhost:3002)
     - [http://localhost:3003](http://localhost:3003)
     - [http://localhost:3012](http://localhost:3012)
     - [http://localhost:3013](http://localhost:3013)
     - [http://localhost:3014](http://localhost:3014)
     - [http://localhost:3015](http://localhost:3015)
     - [http://localhost:3016](http://localhost:3016)
     - [http://localhost:3017](http://localhost:3017)

## Networking

- **Network Name:** `visionai-network`
- **Driver:** `bridge`

## Volumes

- **prometheus_data**
- **grafana_data**

---
