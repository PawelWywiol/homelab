# x201 - Web Apps

Host for self-hosted web applications. Deployed by Ansible from the control
node; not defined in OpenTofu (see [pve/x000/infra](../x000/infra/README.md)).

The host also runs OpenClaw (`192.168.0.201:18789`), which is standalone and
not managed from this repository.

## Services

| Service | Port | Description |
|---------|------|-------------|
| portainer | 9443 | Container management UI |
| glances | - | Host/container metrics |

More will be added as applications land here.

## Operations

```bash
cd pve/x201
make SERVICE [up|down|restart|pull|logs]
```

Targets are discovered from `docker/config/`, so any directory with a
`compose.yml` works.

## Adding an application

1. Create `docker/config/<app>/` with `compose.yml` and `.env.example`
2. Add a Caddy route in [pve/x000/docker/config/caddy/Caddyfile](../x000/docker/config/caddy/Caddyfile)
3. Add an entry to [homepage services.yaml](../x000/docker/config/homepage/config/services.yaml)
4. Push to `main` — the webhook deploys it

Prefer the shared databases on x202 over running another instance here.

## File Sync

```bash
make pull x201   # Server -> Local
make push x201   # Local -> Server
```

Copy `.envrc.example` to `.envrc` and set `REMOTE_HOST` first.

## GitOps

Changes under `pve/x201/docker/config/*` pushed to `main` deploy automatically;
removing a service directory stops and removes its containers.

See [docs/automation](../../docs/automation/README.md).

## Structure

```
docker/config/SERVICE/
├── compose.yml
├── .env              # Secrets (not in git)
└── .env.example      # Template
```
