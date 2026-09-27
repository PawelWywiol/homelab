# x202 - Web Services

**Primary production environment** for web apps and infrastructure services.

## Services

**Infrastructure**:
- portainer - Container management UI
- beszel - System monitoring
- glances - Host/container metrics
- docker-socket-proxy - Scoped Docker API access

**Applications**:
- wakapi - Activity tracker

**Databases**:
- postgres - PostgreSQL + pgAdmin
- redis - Cache/session store
- rabbitmq - Message broker
- mongo - MongoDB + Express UI
- influxdb - Time-series DB
- metrics-influxdb - Host metrics (auth, 90d)

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
make grafana up         # Start Grafana
make postgres add mydb  # Create PostgreSQL database
make redis pull         # Pull latest Redis image
```

The reverse proxy for this host runs on the control node, not here:
see [pve/x000](../x000/README.md).

**Before the first `metrics-influxdb` deploy**, create its `.env` on x202
(the db creates its users only once, on first start with an empty volume;
compose refuses to start without it):
```bash
cd docker/config/metrics-influxdb
cp .env.example .env    # fill in; passwords: openssl rand -hex 24
chmod 600 .env
```
Put the same read password in grafana's `.env` (`METRICS_INFLUXDB_READ_PASSWORD`).

**Changing `metrics-influxdb` retention** (default 90 d): retention is
per-database and set only once, at first start, by the image's init script —
changing `METRICS_RETENTION` in `.env` afterwards has no effect. Change it
live as the admin user:
```bash
docker exec -it metrics-influxdb influx -username <admin_user> -password '' \
  -execute 'ALTER RETENTION POLICY "metrics_rp" ON "metrics" DURATION 180d'
```
See [scripts/metrics-agent/README.md](../../scripts/metrics-agent/README.md)
for the agent that writes to it.

## Structure

```
docker/config/SERVICE/
├── compose.yml
├── .env              # Secrets (not in git)
├── .env.example      # Template
└── README.md         # Service-specific docs
```

See [Makefile](./Makefile) for all targets.
