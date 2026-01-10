# x202 - Web Services

**Primary production environment** for web apps and infrastructure services.

## Services

**Infrastructure**:
- caddy - Reverse proxy
- portainer - Container management UI
- beszel - System monitoring

**Applications**:
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

**Testing**:
- k6 - Load testing (w/ InfluxDB + dashboard extensions)

## Operations

All via Makefile in this directory:

**Generic app management** (works for any service in docker/config/):
```bash
make SERVICE [up|down|restart|pull]
```

**Special commands**:
```bash
make postgres [up|down|restart|pull|add|remove] [DB_NAME]
make glitchtip [up|down|restart|pull|createsuperuser]
make k6-build                    # Build k6 with extensions
make k6-grafana script.js        # Run k6 → InfluxDB
make k6-dashboard script.js      # Run k6 → HTML export
make random                      # Generate 32-byte hex
make help                        # Show all commands
```

**Examples**:
```bash
make caddy up           # Start Caddy reverse proxy
make postgres add mydb  # Create PostgreSQL database
make redis pull         # Pull latest Redis image
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
