# Metrics Setup for Development environment

- Use this folder to bringup prometheus & grafana servers on a local setup (running python server.py).
- This uses host mode for networking allowing `python server.py` to push to a prometheus server collectible by prometheus container.
- `docker-compose up -d` to start the containers.
- `http://localhost:9090` is prometheus URL.
- `http://localhost:9091` is grafana URL.
- `http://localhost:9092` is cadvisor URL.