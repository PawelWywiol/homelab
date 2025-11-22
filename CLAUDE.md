# CLAUDE.md

Guidance for Claude Code when working with this repository.

## Overview

Homelab infrastructure repository with Docker Compose configs and management scripts for self-hosted services. Organized around PVE (Proxmox Virtual Environment) with different directory structures per environment.

**Environment structure**:
- x000: Legacy services → `pve/x000/SERVICE/`
- x201: DNS services → `pve/x201/docker/config/`
- x202: Web/App services → `pve/x202/docker/config/SERVICE/`
- x250: AI/ML services → `pve/x250/docker/config/`
- x203: Future k3s cluster (planned)

**Security**: `.env` files contain secrets. Use `.env.example` for structure reference (keys only, no values).

## Architecture

- **Service Management**: Docker Compose with per-service config directories
- **Environment Config**: Per-service `.env` files for environment variables
- **File Sync**: Scripts for local ↔ server synchronization (defined in `.envrc` SYNC_FILES)
- **Operations**: Makefile-based orchestration in `pve/x202/` (primary environment)

## Commands

### Service Management (x202)

Manage services via Makefile in `pve/x202/`:

```bash
cd pve/x202
make SERVICE [up|down|restart]
```

**Available services**:
- `caddy` - Reverse proxy
- `portainer` - Container management UI
- `n8n` - Workflow automation
- `wakapi` - Coding activity tracker
- `beszel` - System monitoring
- `uptime-kuma` - Uptime monitoring
- `ntfy` - Push notifications
- `grafana` - Dashboards/visualization
- `postgres` - PostgreSQL + pgAdmin
- `redis` - Redis cache
- `rabbitmq` - Message broker
- `mongo` - MongoDB + Mongo Express
- `influxdb` - Time-series DB
- `glitchtip` - Error tracking
- `sonarqube` - Code quality

### Database Operations (x202)

**PostgreSQL**:
```bash
make postgres add DB_NAME      # Create database + user
make postgres remove DB_NAME   # Drop database + user
```

**GlitchTip**:
```bash
make glitchtip createsuperuser  # Create Django admin user
```

### File Sync

Sync local ↔ server via rsync wrapper:

```bash
# Server → Local
./scripts/sync-files.sh user@host ./pve/PATH

# Local → Server
./scripts/sync-files.sh ./pve/PATH user@host
```

Files defined in `.envrc` `SYNC_FILES` array per directory.

### Performance Testing (x202)

K6 load testing with extensions:

```bash
cd pve/x202
make k6-build                     # Build k6 w/ influxdb + dashboard extensions
make k6-grafana script.js         # Run test → InfluxDB
make k6-dashboard script.js       # Run test → HTML dashboard export
```

Script location: `./docker/config/k6/scripts/`

### Utilities

```bash
cd pve/x202
make random    # Generate 32-byte hex secret
make help      # List all targets
```

## Directory Structure

```
pve/
├── x000/SERVICE/              # Legacy: flat structure
│   ├── compose.yml
│   ├── .env
│   └── .env.example
├── x201/                      # DNS services
│   ├── docker/config/
│   └── compose.yml            # Root compose
├── x202/                      # Main web services
│   ├── Makefile              # Primary orchestration
│   ├── docker/config/SERVICE/
│   │   ├── compose.yml
│   │   ├── .env
│   │   └── .env.example
│   └── .envrc                # Sync config
├── x250/                      # AI/ML
│   └── docker/config/
scripts/                       # Init + sync utilities
docs/                         # Guides (docker, linux, proxmox, wsl)
```

## Notes

- **Working directory**: Run Make commands from `pve/x202/` (not service subdirs)
- **Secrets**: Never commit `.env` files; reference `.env.example` for keys
- **Database**: Prefer shared PostgreSQL instance (`pve/x202/docker/config/postgres/`)
- **SSH**: File sync requires SSH key-based auth to server
- **Path structure**: Differs by environment (see Directory Structure above)
