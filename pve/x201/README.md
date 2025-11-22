# x201 - DNS & Network Services

**Infrastructure services** for DNS, reverse proxy, and network management.

## Services

**Network**:
- pihole - DNS server with ad-blocking
- cloudflared - Cloudflare Tunnel
- caddy - Reverse proxy with Cloudflare DNS

**Management**:
- portainer - Container management UI
- beszel-agent - System monitoring agent

## Operations

```bash
docker compose up -d
docker compose down
```

## Structure

```
docker/
├── config/caddy/          # Caddy configuration
│   ├── Caddyfile
│   └── index.html
├── data/                  # Persistent data
│   ├── caddy/
│   ├── pihole/
│   └── portainer/
```

## Notes

- PiHole runs on ports 53 (DNS), 5080 (HTTP), 5443 (HTTPS)
- Caddy handles reverse proxy on ports 80/443
- Beszel agent monitors host system via network_mode: host
