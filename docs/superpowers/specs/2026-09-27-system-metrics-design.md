# System metrics: agent, store and Grafana dashboard — design

Date: 2026-09-27. Status: approved.

## Goal

A Grafana dashboard with every resource metric of a host (CPU, GPU, memory,
disk, network, processes, containers), fed by a lightweight agent installable
and uninstallable by a script from this repo. First host: the Omarchy (Arch)
workstation. Later: Debian/Ubuntu VMs and LXC on Proxmox, Raspberry Pi OS,
macOS, and Proxmox VM/LXC stats. Design for that growth now, implement Linux
with systemd only.

## Decisions and evidence

| Decision | Choice | Why (verified 2026-09-27) |
| --- | --- | --- |
| Collector | Telegraf 1.40.1 | Push model (works behind NAT), one static Go binary; official tarballs for linux amd64/arm64/armhf and darwin arm64; inputs cpu, mem, swap, disk, diskio, net, netstat, system, processes, kernel, temp, nvidia_smi, docker, proxmox exist |
| Store | New InfluxDB 1.13.1 container, db `metrics` | Per-db READ/WRITE users; retention changeable with `ALTER RETENTION POLICY`; InfluxQL like the existing 1.11.8. Rejected: 3 Core (72 h default query cap, fixed retention, admin-only tokens), 2.x (Flux in maintenance), VictoriaMetrics (needs vmauth for split creds, PromQL) |
| Isolation | Separate from existing `influxdb` (1.11.8, no users) | Existing instance and its k6/claude data stay untouched |
| Interval / retention | 10 s / 90 d | Interval per host (installer flag or config edit); retention per db, server-side only |
| Install mode | Native systemd service | Full GPU/sensor access; no `nvidia-container-toolkit` on this host; container cannot see a macOS host |
| Endpoint | `https://metrics.local.wywiol.eu` via Caddy on x000 | Agent credentials travel over TLS. The db port on x202 is still reachable on the LAN (Caddy proxies over it); auth protects it |
| Docker stats | Only with `--docker` | Docker socket access is root-equivalent |
| Temperatures | `inputs.temp` (sysfs) | No `lm_sensors` dependency |

Verified facts relied on:

- `influxdb:1.13` image `init-influxdb.sh` creates `INFLUXDB_WRITE_USER` /
  `INFLUXDB_READ_USER` and runs `GRANT WRITE` / `GRANT READ` on `INFLUXDB_DB`
  — only on first start (empty meta dir).
- Telegraf tarballs ship `.asc` signatures, no `.sha256`. Signing key
  fingerprint `24C9 75CB A61A 024E E1B6 3178 7C3D 5715 9FC2 F927`.
- Tarball contains `usr/bin/telegraf` and `usr/lib/telegraf/scripts/telegraf.service`
  (`User=telegraf`, `-config-directory /etc/telegraf/telegraf.d`).
- Telegraf buffers unsent metrics in memory and overwrites the oldest when
  `metric_buffer_limit` is reached; default value not found in docs, so set
  explicitly.
- `influxdb:latest` moved to InfluxDB 3 Core on 2026-09-15 — pin tags.

## Architecture

```
host: telegraf (systemd, 10 s) --HTTPS--> Caddy x000 metrics.local.wywiol.eu
                                            --> x202:8087 metrics-influxdb 1.13.1 (auth)
grafana (x202, docker network, read-only user) --> dashboard "System Metrics"
```

## Repository layout

| Path | Content |
| --- | --- |
| `scripts/metrics-agent/install.sh` | `install`, `uninstall`, `status`; root; works via `curl \| sudo bash -s --` |
| `scripts/metrics-agent/telegraf/*.conf` | fragments: `base` (agent + output), `linux`, `nvidia`, `docker`; `darwin` later |
| `scripts/metrics-agent/README.md` | install, flags, changing interval, uninstall, measured overhead |
| `scripts/tests/test-metrics-agent.sh` | tests in the style of the existing suite |
| `pve/x202/docker/config/metrics-influxdb/` | `compose.yml`, `.env.example`: db `metrics`, users `telegraf` (write), `grafana` (read), 90 d default retention |
| `pve/x202/docker/config/grafana/provisioning/` | datasource `metrics-influxdb` (`jsonData.dbName`), `dashboards/system-metrics.json` |
| `pve/x000/docker/config/caddy/Caddyfile`, homepage config | `metrics` route + entry |
| `CLAUDE.md`, `scripts/README.md`, `pve/x202/README.md`, `docs/README.md` | kept current |

## Installer

- Downloads the official Telegraf tarball for the arch, verifies the `.asc`
  with `gpg` against the pinned fingerprint, then installs
  `/usr/local/bin/telegraf`, `/etc/telegraf/`, the systemd unit and the
  `telegraf` system user.
- Flags: `--url`, `--interval` (default `10s`), `--host` (default hostname),
  `--docker`, `--ref` (repo ref for config fragments). Password from an env var
  or an interactive prompt, never a flag.
- Config fragments are fetched from the repo at `--ref` when there is no local
  script directory (`curl | bash` has none — see the `init-host.sh` gotcha).
- Re-run = update: binary and fragments replaced; password, interval, host and
  docker choice kept unless given again.
- New config is checked with `telegraf --test` before it replaces the old one
  and the service restarts; on failure the old config and service stay.
- `uninstall` removes everything `install` created.
- Unsupported OS/init system: clear message, non-zero exit.
- Tags on every point: `host`, `os`.

## Dashboard "System Metrics"

- Variable `host` (single). Default range 6 h, refresh 30 s. 24-col grid,
  graph panels 12 wide.
- One axis and one unit per panel. Legend as table: Min, Max, Mean, Last,
  sorted by Mean. Thresholds green/yellow/red with value and unit.
  Fixed colours for rx/tx.
- Rows below Overview collapsible (collapsed rows do not query).

| Row | Panels |
| --- | --- |
| Overview (stat + sparkline) | uptime, CPU %, load per core, RAM %, swap %, `/` %, CPU temp, GPU %, GPU temp, net ↓/↑ now |
| CPU | usage by mode (user/system/iowait/steal), per-core usage, load 1/5/15, sensor temperatures |
| Memory | used/cache/buffers/available; swap |
| GPU (NVIDIA) | util GPU/mem %, VRAM used/total, temperature, power vs limit, fan |
| Disk | usage per mount (bar gauge), read/write B/s, IOPS, device busy % |
| Network | ↓/↑ per interface (tx mirrored below axis), errors/drops, TCP by state |
| System | processes by state, threads, context switches, interrupts |
| Docker (collapsed) | CPU, memory, network per container; only hosts with `--docker` |

A future "Fleet" dashboard lists all hosts in one table.

## Testing and verification

Automated:
- `shellcheck` on the installer.
- Install into a temp root prefix (no root, host untouched): files present;
  second install byte-identical; `uninstall` leaves the prefix empty;
  re-install without a password keeps password and interval.
- Dashboard and datasource parse; every query references a measurement the
  fragments produce.
- `docker compose config` for `metrics-influxdb`.

Live (evidence recorded in READMEs):
1. `metrics-influxdb` up on x202, Caddy route live.
2. Agent installed on this workstation; `systemctl status telegraf` active.
3. All measurements arrive for this host.
4. `telegraf` user cannot read; `grafana` user cannot write.
5. Telegraf CPU % and RSS over 10 min.
6. Dashboard opened in Grafana and screenshotted.
7. Re-install (update), `uninstall`, install again.

## Out of scope (later phases)

- Claude Code token stats — blocked on fixing `scripts/claude-statusline.sh`,
  which re-sums values that are already totals.
- Debian/Ubuntu/RPi apt install path, macOS launchd, Proxmox `inputs.proxmox`
  (PVEAuditor token), Fleet dashboard.
- Firewalling the db port on x202.

## Deployment (resolved)

1. User pushes to `main` (webhook deploys); assistant verifies afterwards.
   Assistant never commits or pushes.
2. Assistant generates passwords locally; user creates
   `pve/x202/docker/config/metrics-influxdb/.env` and adds the read password to
   grafana `.env` on x202.
3. Port 8087 is checked free on x202 before deploy.
