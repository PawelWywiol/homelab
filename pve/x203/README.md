# x203 - File Sharing

Storage and media VM. Deployed by Ansible from the control node; not defined in
OpenTofu (see [pve/x000/infra](../x000/infra/README.md)).

## Services

| Service | Port | Description |
|---------|------|-------------|
| samba | 139, 445 | SMB file sharing |
| share | 8081, 6881, 8080 | qBittorrent + media stack |
| portainer | 9443 | Container management UI |
| glances | - | Host/container metrics |
| docker-socket-proxy | 2375 | Scoped Docker API access |

The `share` stack bundles qBittorrent behind a gluetun VPN container, plus
deunhealth, chromium, romifleur, filebrowser and romm (with its MariaDB).

## Operations

```bash
cd pve/x203
make SERVICE [up|down|restart|pull|logs]
```

Targets are discovered from `docker/config/`, so any directory with a
`compose.yml` works. No special commands on this host.

## File Sync

```bash
make pull x203   # Server -> Local
make push x203   # Local -> Server
```

Copy `.envrc.example` to `.envrc` and set `REMOTE_HOST` first.

## GitOps

Changes under `pve/x203/docker/config/*` pushed to `main` deploy automatically;
removing a service directory stops and removes its containers.

See [docs/automation](../../docs/automation/README.md).

## Structure

```
docker/config/SERVICE/
├── compose.yml
├── .env              # Secrets (not in git)
└── .env.example      # Template
```
