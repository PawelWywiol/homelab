# Homelab Infrastructure

Proxmox-based homelab with Docker Compose service orchestration.

## Quick Start

**Primary environment** (x202):
```bash
cd pve/x202
make SERVICE [up|down|restart]  # See CLAUDE.md for service list
```

## File Sync

Sync configuration between local and server:

```bash
# Server → Local
./scripts/sync-files.sh user@host ./pve/PATH

# Local → Server
./scripts/sync-files.sh ./pve/PATH user@host
```

Config: Define files in `pve/*/.envrc` `SYNC_FILES` array.

## Environments

- **x000**: Legacy services (deprecated)
- **x201**: DNS/network services
- **x202**: Web/application services (primary)
- **x250**: AI/ML workloads
- **x203**: K3s cluster (planned)

## Documentation

- **[CLAUDE.md](./CLAUDE.md)** - Full setup guide + commands
- **[docs/](./docs/)** - Docker, Linux, Proxmox, WSL guides
- **[scripts/](./scripts/)** - Init scripts + utilities

## Structure

```
pve/x202/                    # Primary environment
├── Makefile                 # Service orchestration
├── docker/config/SERVICE/   # Per-service configs
│   ├── compose.yml
│   ├── .env
│   └── .env.example
└── .envrc                   # Sync configuration
```

See [CLAUDE.md](./CLAUDE.md) for complete documentation.
