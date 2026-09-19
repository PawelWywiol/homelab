# Archived Services

**Status**: Not deployed - kept for reference

Nothing here is picked up by Makefiles, Ansible or the GitOps webhook.

**Environments**:

- x250 - AI/ML on AMD ROCm (ollama, open-webui, stable diffusion)

**Services** (flat structure, each with own compose.yml):

- caddy - Reverse proxy
- cloudflared - Cloudflare Tunnel
- emulatorjs - Retro game emulation
- glitchtip - Error tracking
- k6 - Load testing
- marqo - Vector search
- ntfy - Push notifications
- passbolt - Password manager
- qbittorrent - Torrent client w/ VPN
- romm - ROM manager
- samba - File sharing
- sitespeed - Performance monitoring
- sonarqube - Code quality
- traefik - Reverse proxy
- uptime-kuma - Uptime monitoring
- wakapi - Activity tracking

**Restoring**: move service dir to `pve/ENV/docker/config/SERVICE/` (or env dir back to `pve/ENV/`)
and align with the env structure.
