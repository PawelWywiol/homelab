# metrics-agent

Installs [Telegraf](https://www.influxdata.com/time-series-platform/telegraf/)
as a systemd service that pushes CPU, memory, disk, network, GPU (NVIDIA) and,
optionally, Docker container metrics to a central InfluxDB 1.x store every
10 s, for the Grafana "System Metrics" dashboard. Design and rationale:
[docs/superpowers/specs/2026-09-27-system-metrics-design.md](../../docs/superpowers/specs/2026-09-27-system-metrics-design.md).

Linux with systemd only for now (see [Roadmap](#roadmap)).

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/PawelWywiol/homelab/main/scripts/metrics-agent/install.sh -o /tmp/metrics-install.sh
sudo METRICS_PASSWORD='…' bash /tmp/metrics-install.sh install            # defaults: 10s, hostname, no docker
sudo bash /tmp/metrics-install.sh install --interval 30s --docker          # update; password kept
sudo bash /tmp/metrics-install.sh status
sudo bash /tmp/metrics-install.sh uninstall
```

`METRICS_PASSWORD` is the `telegraf` write user's InfluxDB password (ask
whoever deployed `metrics-influxdb`). Without it, and with no password stored
from a previous install, the script prompts on `/dev/tty` — set the env var
when there is no terminal to prompt on (e.g. a provisioning script). Piping
through `curl | sudo bash -s -- install` works too (note the `-s --`, without
it bash eats the flags); the download-then-run form above just also lets you
re-run the local copy for `status`/`uninstall`.

Re-running `install` **updates**: the binary and config fragments are
replaced, and every setting not given again is kept from the previous install
(including the password).

### Flags (`install`)

| Flag | Default | Meaning |
| --- | --- | --- |
| `--url URL` | `https://metrics.local.wywiol.eu` (or stored) | InfluxDB write endpoint |
| `--interval DUR` | `10s` (or stored) | Telegraf collection/flush interval |
| `--host NAME` | `$(hostname)` (or stored) | `host` tag on every point |
| `--docker` | off | Collect Docker container stats via `/var/run/docker.sock` |
| `--docker-endpoint URL` | — | Same as `--docker` with a non-default socket/URL |
| `--no-docker` | — | Turn Docker collection back off on an update |
| `--ref REF` | `main` | Git ref to fetch config fragments from (piped installs only; a local checkout uses its own files) |

Every value (`--url`, the password, `--interval`, `--host`, the Docker
endpoint) must match `^[A-Za-z0-9._~:/@+=,-]*$` — no spaces or quotes. It ends
up in a TOML string, a systemd `EnvironmentFile` and a shell word, so this is
enforced instead of trying to escape it in three different places. A generated
hex password (`openssl rand -hex 24`) is always safe.

`status` prints the installed Telegraf version, the stored settings (password
redacted) and `systemctl status telegraf`. `uninstall` removes everything
`install` created, including the `telegraf` system user.

### Files installed

| Path | Content |
| --- | --- |
| `/usr/local/bin/telegraf` | Telegraf binary, GPG-verified against InfluxData's key on download |
| `/etc/telegraf/telegraf.conf` | Agent + output config (`base.conf`) |
| `/etc/telegraf/telegraf.d/*.conf` | Input fragments: `linux.conf` always, `nvidia.conf` if `nvidia-smi` is found, `docker.conf` if Docker collection is on |
| `/etc/default/telegraf` | Mode `600`; `METRICS_URL`, `METRICS_PASSWORD`, `METRICS_INTERVAL`, `METRICS_HOST`, `METRICS_OS` (from `/etc/os-release`), `METRICS_DOCKER_ENDPOINT` |
| `/etc/systemd/system/telegraf.service` | `Type=notify`, runs as the `telegraf` system user |

A new config is checked with `telegraf --test` before it replaces the running
one; if it fails, the previous config and service are left untouched.

**Docker socket access is root-equivalent.** With `--docker` (default
endpoint), the `telegraf` user is added to the `docker` group so it can read
`/var/run/docker.sock` — anyone who can reach that socket can escalate to
root on the host. Only enable it on hosts where that trade-off is acceptable.

## Changing settings after install

**Interval, without re-running the installer:** edit `METRICS_INTERVAL=` in
`/etc/default/telegraf`, then `systemctl restart telegraf`. Re-running
`install --interval DUR` does the same plus re-validates the config and
re-fetches the fragments; either works.

**Retention** (default 90 d, set at `metrics-influxdb` deploy time) is
per-database, server-side, and not something the agent controls. An admin
with the InfluxDB admin password changes it on `metrics-influxdb`:

```bash
docker exec -it metrics-influxdb influx -username <admin_user> -password '' \
  -execute 'ALTER RETENTION POLICY "metrics_rp" ON "metrics" DURATION 180d'
```

`-password ''` makes `influx` prompt for the password interactively instead
of taking it as an argument — needs `-it` (verified: without a TTY it fails
with `unable to prompt for a password with no TTY` rather than silently using
an empty password). Passing the real password on the command line instead
would put it in that container's process list (`docker top metrics-influxdb`),
visible to anything else able to exec into it.

## Verified against

| Component | Version | Source |
| --- | --- | --- |
| Telegraf | 1.40.1 | `install.sh` (`TELEGRAF_VERSION`), GPG-verified tarball |
| InfluxDB | 1.13.1 | `pve/x202/docker/config/metrics-influxdb/compose.yml` image tag |
| Grafana | 12.0.0 | `pve/x202/docker/config/grafana/compose.yml` image tag |
| OS / kernel | Arch Linux (Omarchy), `7.2.5-3-omarchy` | `uname -r` on the workstation |
| NVIDIA driver | 610.57.04 | `nvidia-smi --query-gpu=driver_version --format=csv,noheader` |
| Telegraf CPU / RSS over 10 min | _to be measured after deployment (Task 7)_ | — |

## Roadmap

- Debian/Ubuntu/Raspberry Pi OS install path (apt-based Telegraf package)
- macOS agent (launchd instead of systemd)
- Proxmox host/VM/LXC stats (`inputs.proxmox`, `PVEAuditor` API token)
- "Fleet" dashboard listing all hosts in one table
- Claude Code token stats, blocked on fixing `scripts/claude-statusline.sh`
  (it re-sums values that are already totals)
