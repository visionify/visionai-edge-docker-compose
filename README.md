# VisionAI Edge Platform - Installation Guide

## Overview

The VisionAI Edge Platform is a comprehensive AI inference solution that includes monitoring, model serving, and image processing capabilities. This Docker Compose setup provides a complete deployment environment for edge AI applications.

## Prerequisites

### System Requirements
- **OS**: Linux (Ubuntu 20.04+ recommended)
- **Docker**: Version 20.10+
- **Docker Compose**: Version 2.0+
- **NVIDIA GPU**: Compatible with CUDA 12.4+
- **NVIDIA Docker**: Runtime with GPU support
- **RAM**: Minimum 8GB, Recommended 16GB+
- **Storage**: Minimum 50GB available space

### Software Dependencies
```bash
# Install Docker (if not already installed)
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Install NVIDIA Docker (for GPU support)
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -
curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | sudo tee /etc/apt/sources.list.d/nvidia-docker.list
sudo apt-get update && sudo apt-get install -y nvidia-docker2
sudo systemctl restart docker
```

## Quick Start

### 1. Clone and Setup
```bash
# Clone the repository
git clone <repository-url>
cd visionai-edge-docker-compose

# Create environment file
cp .env.example .env
```

### 2. Configure Environment
Edit the `.env` file with your specific configuration:

```bash
# Essential configuration
VISIONAI_TAG=test                    # or 'latest' for production
INSTANCE_ID=1                        # Unique instance identifier
GPU_COUNT=1                          # Number of available GPUs
GRAFANA_ADMIN_PASSWORD=admin         # Change for production!

# Paths (modify as needed)
VISIONAI_DATA_PATH=${HOME}/.visionai
MODELS_PATH=${HOME}/.visionai/models-repo
SCREENSHOTS_PATH=${HOME}/.visionai/screenshots
```

### 3. Prepare Directories
```bash
# Create necessary directories
mkdir -p ${HOME}/.visionai/{models-repo,screenshots}
mkdir -p prometheus grafana/{datasources,dashboards}

# Set proper permissions
chmod 755 ${HOME}/.visionai
```

### 4. Deploy Services
```bash
# Start all services
docker-compose up -d

# Check service status
docker-compose ps

# View logs
docker-compose logs -f
```

## Service Architecture

### Core Services

| Service | Port | Description | Health Check |
|---------|------|-------------|--------------|
| **Prometheus** | 9090 | Metrics collection and storage | `http://localhost:9090/-/healthy` |
| **Grafana** | 9091 | Metrics visualization | `http://localhost:9091/api/health` |
| **Triton** | 8000-8002 | AI model serving | `http://localhost:8000/v2/health/ready` |
| **Inference** | 3002-3003 | AI processing engine | `http://localhost:3003/health` |
| **Screenshots** | 8080 | Image capture service | `http://localhost:8080/health` |

### Network Configuration
- **Network**: `visionai-network` (172.20.0.0/16)
- **Bridge**: Internal communication between services
- **External**: Ports exposed for monitoring and API access

## Configuration Options

### Environment Variables

#### Essential Variables
- `VISIONAI_TAG`: Docker image tag (test/latest)
- `INSTANCE_ID`: Unique instance identifier
- `GPU_COUNT`: Number of GPUs to allocate
- `GRAFANA_ADMIN_PASSWORD`: Grafana admin password

#### Path Configuration
- `VISIONAI_DATA_PATH`: Main data directory
- `MODELS_PATH`: AI models repository
- `SCREENSHOTS_PATH`: Image storage location

#### Monitoring
- `LOG_LEVEL`: Service logging level (DEBUG/INFO/WARNING/ERROR)
- `PROMETHEUS_RETENTION`: Metrics retention period

### Volume Management
```bash
# View volumes
docker volume ls

# Backup data
docker run --rm -v visionai-edge-docker-compose_prometheus_data:/data -v $(pwd):/backup alpine tar czf /backup/prometheus_backup.tar.gz -C /data .

# Restore data
docker run --rm -v visionai-edge-docker-compose_prometheus_data:/data -v $(pwd):/backup alpine tar xzf /backup/prometheus_backup.tar.gz -C /data
```

## Monitoring and Troubleshooting

### Health Checks
All services include health checks. Monitor them with:
```bash
# Check all service health
docker-compose ps

# View health check logs
docker-compose logs | grep -i health
```

### Logs and Debugging
```bash
# View all logs
docker-compose logs -f

# View specific service logs
docker-compose logs -f visionai-inference

# Debug container
docker-compose exec visionai-inference bash
```

### Common Issues

#### GPU Not Detected
```bash
# Check NVIDIA Docker installation
docker run --rm --gpus all nvidia/cuda:11.8-base-ubuntu20.04 nvidia-smi

# Verify GPU allocation
docker-compose exec visionai-triton nvidia-smi
```

#### Port Conflicts
```bash
# Check port usage
sudo netstat -tulpn | grep -E ':(9090|9091|8000|3002|8080)'

# Modify ports in docker-compose.yml if needed
```

#### Permission Issues
```bash
# Fix directory permissions
sudo chown -R $USER:$USER ${HOME}/.visionai
chmod -R 755 ${HOME}/.visionai
```

## Production Deployment

### Security Considerations
1. **Change default passwords** in `.env`
2. **Use specific image tags** instead of `latest`
3. **Configure firewall rules** for exposed ports
4. **Enable SSL/TLS** for external access
5. **Regular backups** of volumes and data

### Performance Optimization
1. **GPU allocation**: Adjust `GPU_COUNT` based on available hardware
2. **Memory limits**: Set appropriate memory limits for containers
3. **Storage**: Use SSD storage for better I/O performance
4. **Network**: Configure proper network isolation

### Scaling
```bash
# Scale inference instances
docker-compose up -d --scale visionai-inference=3

# Load balancing configuration
# (Add reverse proxy like nginx for multiple instances)
```

## Maintenance

### Updates
```bash
# Update images
docker-compose pull

# Restart services with new images
docker-compose up -d

# Clean up old images
docker image prune -f
```

### Backups
```bash
# Create backup script
#!/bin/bash
BACKUP_DIR="/backup/visionai-$(date +%Y%m%d_%H%M%S)"
mkdir -p $BACKUP_DIR

# Backup volumes
docker run --rm -v visionai-edge-docker-compose_prometheus_data:/data -v $BACKUP_DIR:/backup alpine tar czf /backup/prometheus_data.tar.gz -C /data .
docker run --rm -v visionai-edge-docker-compose_grafana_data:/data -v $BACKUP_DIR:/backup alpine tar czf /backup/grafana_data.tar.gz -C /data .

# Backup configuration
cp docker-compose.yml $BACKUP_DIR/
cp .env $BACKUP_DIR/
```

## Support

For technical support and issues:
- Check service logs: `docker-compose logs`
- Verify configuration: `docker-compose config`
- Test connectivity: `curl http://localhost:3003/health`

## License

This project is licensed under the terms specified in the LICENSE file.

---
