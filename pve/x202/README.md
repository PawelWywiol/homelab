# x202 - Web Services

**Primary production environment** for web apps and infrastructure services.

## Services

**Infrastructure**:
- caddy - Reverse proxy
- portainer - Container management UI
- beszel - System monitoring
- uptime-kuma - Uptime monitoring

**Applications**:
- n8n - Workflow automation
- wakapi - Activity tracker
- ntfy - Push notifications

**Databases**:
- postgres - PostgreSQL + pgAdmin
- redis - Cache/session store
- rabbitmq - Message broker
- mongo - MongoDB + Express UI
- influxdb - Time-series DB

**Dev Tools**:
- grafana - Dashboards
- glitchtip - Error tracking
- sonarqube - Code quality

**Testing**:
- k6 - Load testing (w/ InfluxDB + dashboard extensions)

## Operations

All via Makefile in this directory:

```bash
make SERVICE [up|down|restart]
make postgres [add|remove] DB_NAME
make glitchtip createsuperuser
make k6-build
make k6-grafana script.js
make random
make help
```

## Structure

```
docker/config/SERVICE/
├── compose.yml
├── .env              # Secrets (not in git)
├── .env.example      # Template
└── README.md         # Service-specific docs
```

See [Makefile](./Makefile) for all targets.
