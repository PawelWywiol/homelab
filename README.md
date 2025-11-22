# Homelab Infrastructure

Proxmox-based homelab with Docker Compose service orchestration.

## Quick Start

**Primary environment** (x202):
```bash
cd pve/x202
make SERVICE [up|down|restart]  # See CLAUDE.md for service list
```

## File Sync

Sync configuration between local and server using Makefile shortcuts:

```bash
# Pull: Server → Local
make pull user@HOST  # e.g., make pull code@x202

# Push: Local → Server
make push user@HOST  # e.g., make push code@x202
```

HOST must match a directory in `pve/` (x000, x201, x202, x250).

**Direct script usage:**
```bash
./scripts/sync-files.sh user@host ./pve/PATH  # Server → Local
./scripts/sync-files.sh ./pve/PATH user@host  # Local → Server
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
