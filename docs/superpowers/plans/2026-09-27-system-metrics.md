# System Metrics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Telegraf agent installed by a script from this repo pushes host metrics every 10 s to a new authenticated InfluxDB 1.13.1 on x202, shown on a provisioned Grafana dashboard "System Metrics".

**Architecture:** Static Telegraf config fragments (no templating) read their per-host values from `/etc/default/telegraf` via `${VAR}` substitution; `install.sh` only writes that env file, copies fragments, installs a GPG-verified binary and a systemd unit. Server side is one compose service plus Grafana provisioning and a Caddy route.

**Tech Stack:** bash, Telegraf 1.40.1, InfluxDB 1.13.1 (`influxdb:1.13.1-alpine`), Grafana 12.0.0, Caddy, Docker Compose.

**Spec:** `docs/superpowers/specs/2026-09-27-system-metrics-design.md`

## Global Constraints

- Telegraf `1.40.1`; InfluxData signing key fingerprint `24C975CBA61A024EE1B631787C3D57159FC2F927`.
- InfluxDB image pinned `influxdb:1.13.1-alpine`; never `latest`.
- Database `metrics`; users `telegraf` (WRITE), `grafana` (READ); default retention `90d`.
- Endpoint `https://metrics.local.wywiol.eu` → `192.168.0.202:8087`.
- Defaults: interval `10s`, host = `hostname`, Docker off.
- Password never passed as a CLI flag.
- Linux + systemd only in this plan; anything else exits non-zero with a message.
- English in code, comments and docs. No commits or pushes by the assistant (user rule) — every "Commit" step is replaced by "stage nothing; list changed files".
- Never mention any `.claude` folder in project files except inside `homelab/.claude/`.

## Verified facts this plan relies on (2026-09-27)

- `telegraf --test` exits 1 on invalid TOML or unknown options; `telegraf config check --config F` exits 1/0. `--test` does not run outputs.
- Telegraf ≥1.38 uses strict env handling: an unset `${VAR}` in `interval` fails parsing, so the env file must be loaded before validating.
- Tarball `telegraf-1.40.1_linux_{amd64,arm64,armhf}.tar.gz` + `.asc`; binary at `telegraf-1.40.1/usr/bin/telegraf`. `gpg --status-fd 1 --verify` prints `VALIDSIG … 24C975CBA61A024EE1B631787C3D57159FC2F927` (primary fpr last).
- Measurements/fields on this host (from `--test`): `cpu` (tag `cpu`, `usage_*`), `mem` (`used`, `cached`, `buffered`, `available`, `used_percent`), `swap` (`used`, `used_percent`), `system` (`load1/5/15`, `n_cpus`, `uptime`), `disk` (tag `path`, `used_percent`, `used`, `total`), `diskio` (tag `name`, `read_bytes`, `write_bytes`, `reads`, `writes`, `io_time`), `net` (tag `interface`, `bytes_recv`, `bytes_sent`, `err_in/out`, `drop_in/out`), `netstat` (`tcp_*`), `processes` (`running`, `sleeping`, `blocked`, `zombies`, `total_threads`), `kernel` (`context_switches`, `interrupts`), `temp` (tag `sensor`, e.g. `coretemp_package_id_0`), `nvidia_smi` (`utilization_gpu`, `utilization_memory`, `memory_used`, `memory_total` [MiB], `temperature_gpu`, `power_draw`, `power_limit`, `fan_speed`), `docker_container_cpu|mem|net` (tag `container_name`; `usage_percent`, `usage`, `rx_bytes`, `tx_bytes`).
- ~80 points per 10 s on this host.
- `influxdb:1.13` `init-influxdb.sh` runs only when the meta dir is absent; with `INFLUXDB_HTTP_AUTH_ENABLED=true` + `INFLUXDB_ADMIN_USER` it creates `INFLUXDB_DB`, `INFLUXDB_WRITE_USER` (GRANT WRITE), `INFLUXDB_READ_USER` (GRANT READ), then **sources** `/docker-entrypoint-initdb.d/*.sh` with `$INFLUX_CMD` (admin client) in scope. Data volume `/var/lib/influxdb`; runs as uid 1500.
- Compose relative volume paths resolve against the compose file dir (Makefile runs `docker compose -f ./docker/config/SVC/compose.yml`).
- Grafana and all x202 services share external network `caddy_network`.

## File map

| File | Responsibility |
| --- | --- |
| `pve/x202/docker/config/metrics-influxdb/compose.yml` | the store |
| `pve/x202/docker/config/metrics-influxdb/.env.example` | its secrets (keys only) |
| `pve/x202/docker/config/metrics-influxdb/initdb/retention.sh` | first-start retention policy |
| `scripts/metrics-agent/telegraf/base.conf` | agent + output |
| `scripts/metrics-agent/telegraf/linux.conf` | host inputs |
| `scripts/metrics-agent/telegraf/nvidia.conf` | GPU input |
| `scripts/metrics-agent/telegraf/docker.conf` | container input |
| `scripts/metrics-agent/telegraf/telegraf.service` | systemd unit |
| `scripts/metrics-agent/install.sh` | install / uninstall / status |
| `scripts/metrics-agent/README.md` | usage + evidence |
| `scripts/tests/test-metrics-agent.sh` | tests |
| `pve/x202/docker/config/grafana/provisioning/datasources/datasource.yml` | + `metrics-influxdb` |
| `pve/x202/docker/config/grafana/compose.yml`, `.env.example` | + read password env |
| `pve/x202/docker/config/grafana/provisioning/dashboards/system-metrics.json` | dashboard |
| `pve/x000/docker/config/caddy/Caddyfile` | route |
| `pve/x000/docker/config/homepage/config/services.yaml` | entry |
| `CLAUDE.md`, `scripts/README.md`, `pve/x202/README.md`, `docs/README.md`, `.claude/docs/*` | docs |

---

### Task 1: metrics-influxdb service

**Files:**
- Create: `pve/x202/docker/config/metrics-influxdb/compose.yml`
- Create: `pve/x202/docker/config/metrics-influxdb/.env.example`
- Create: `pve/x202/docker/config/metrics-influxdb/initdb/retention.sh`

**Interfaces:**
- Produces: container `metrics-influxdb` on `caddy_network`, host port `8087`, db `metrics`, RP `metrics_rp` (default), users `telegraf`/`grafana`; env keys `METRICS_INFLUXDB_ADMIN_USER`, `METRICS_INFLUXDB_ADMIN_PASSWORD`, `METRICS_INFLUXDB_WRITE_PASSWORD`, `METRICS_INFLUXDB_READ_PASSWORD`, `METRICS_RETENTION`.

- [ ] **Step 1: Write compose.yml**

```yaml
---
services:
  metrics-influxdb:
    container_name: metrics-influxdb
    image: influxdb:1.13.1-alpine
    ports:
      - 8087:8086
    environment:
      - INFLUXDB_HTTP_AUTH_ENABLED=true
      - INFLUXDB_DB=metrics
      - INFLUXDB_ADMIN_USER=${METRICS_INFLUXDB_ADMIN_USER}
      - INFLUXDB_ADMIN_PASSWORD=${METRICS_INFLUXDB_ADMIN_PASSWORD}
      - INFLUXDB_WRITE_USER=telegraf
      - INFLUXDB_WRITE_USER_PASSWORD=${METRICS_INFLUXDB_WRITE_PASSWORD}
      - INFLUXDB_READ_USER=grafana
      - INFLUXDB_READ_USER_PASSWORD=${METRICS_INFLUXDB_READ_PASSWORD}
      - METRICS_RETENTION=${METRICS_RETENTION:-90d}
    volumes:
      - metrics_influxdb_data:/var/lib/influxdb
      - ./initdb:/docker-entrypoint-initdb.d:ro
    networks:
      - caddy_network
    restart: unless-stopped

volumes:
  metrics_influxdb_data:
    name: metrics_influxdb_data
    driver: local

networks:
  caddy_network:
    name: caddy_network
    external: true
```

- [ ] **Step 2: Write .env.example**

```
METRICS_INFLUXDB_ADMIN_USER=
METRICS_INFLUXDB_ADMIN_PASSWORD=
METRICS_INFLUXDB_WRITE_PASSWORD=
METRICS_INFLUXDB_READ_PASSWORD=
METRICS_RETENTION=90d
```

- [ ] **Step 3: Write initdb/retention.sh** (mode 644; it is sourced, not executed)

```sh
# Sourced by the image's init-influxdb.sh on the first start only; $INFLUX_CMD is its admin client.
# Later changes: ALTER RETENTION POLICY "metrics_rp" ON "metrics" DURATION <d>
$INFLUX_CMD "CREATE RETENTION POLICY \"metrics_rp\" ON \"metrics\" DURATION ${METRICS_RETENTION:-90d} REPLICATION 1 DEFAULT"
```

- [ ] **Step 4: Validate compose**

Run: `cd pve/x202 && docker compose --env-file ./docker/config/metrics-influxdb/.env.example -f ./docker/config/metrics-influxdb/compose.yml config -q; echo rc=$?`
Expected: `rc=0` (creating `caddy_network` is not needed for `config`).

- [ ] **Step 5: Local smoke test with a throwaway container** (not on x202; no `caddy_network` needed)

```bash
docker run -d --rm --name mi-smoke -p 127.0.0.1:18087:8086 \
  -e INFLUXDB_HTTP_AUTH_ENABLED=true -e INFLUXDB_DB=metrics \
  -e INFLUXDB_ADMIN_USER=admin -e INFLUXDB_ADMIN_PASSWORD=adminpw \
  -e INFLUXDB_WRITE_USER=telegraf -e INFLUXDB_WRITE_USER_PASSWORD=wpw \
  -e INFLUXDB_READ_USER=grafana -e INFLUXDB_READ_USER_PASSWORD=rpw \
  -e METRICS_RETENTION=90d \
  -v "$PWD/pve/x202/docker/config/metrics-influxdb/initdb:/docker-entrypoint-initdb.d:ro" \
  influxdb:1.13.1-alpine
sleep 8
q() { curl -s -u "$1" -G http://127.0.0.1:18087/query --data-urlencode "db=metrics" --data-urlencode "q=$2"; echo; }
q admin:adminpw 'SHOW RETENTION POLICIES ON metrics'
q admin:adminpw 'SHOW GRANTS FOR telegraf'
q admin:adminpw 'SHOW GRANTS FOR grafana'
curl -s -o /dev/null -w 'telegraf write %{http_code}\n' -u telegraf:wpw -XPOST 'http://127.0.0.1:18087/write?db=metrics' --data-binary 'smoke v=1'
curl -s -o /dev/null -w 'grafana write %{http_code}\n'  -u grafana:rpw  -XPOST 'http://127.0.0.1:18087/write?db=metrics' --data-binary 'smoke v=1'
q telegraf:wpw 'SELECT * FROM smoke'
q grafana:rpw  'SELECT * FROM smoke'
curl -s -o /dev/null -w 'anon %{http_code}\n' -G http://127.0.0.1:18087/query --data-urlencode 'q=SHOW DATABASES'
docker stop mi-smoke
```

Expected: RP `metrics_rp` `2160h0m0s` default=true; telegraf grant `WRITE`, grafana `READ`; `telegraf write 204`, `grafana write 403`; telegraf SELECT → error "not authorized"; grafana SELECT → the `smoke` row; `anon 401`.

- [ ] **Step 6: List changed files** (no commit).

---

### Task 2: Telegraf config fragments and unit

**Files:**
- Create: `scripts/metrics-agent/telegraf/base.conf`, `linux.conf`, `nvidia.conf`, `docker.conf`, `telegraf.service`

**Interfaces:**
- Consumes: env vars `METRICS_URL`, `METRICS_PASSWORD`, `METRICS_INTERVAL`, `METRICS_HOST`, `METRICS_OS`, `METRICS_DOCKER_ENDPOINT` (only for docker.conf).
- Produces: files installed verbatim by Task 3: `base.conf` → `/etc/telegraf/telegraf.conf`; others → `/etc/telegraf/telegraf.d/`; unit → `/etc/systemd/system/telegraf.service`.

- [ ] **Step 1: base.conf**

```toml
# Per-host values come from /etc/default/telegraf, written by install.sh.
[global_tags]
  os = "${METRICS_OS}"

[agent]
  interval = "${METRICS_INTERVAL}"
  round_interval = true
  flush_interval = "${METRICS_INTERVAL}"
  flush_jitter = "2s"
  metric_batch_size = 1000
  # ~80 points per 10 s on a desktop: about 1.5 h of outage before the oldest are dropped.
  metric_buffer_limit = 50000
  hostname = "${METRICS_HOST}"
  omit_hostname = false
  skip_processors_after_aggregators = true

[[outputs.influxdb]]
  urls = ["${METRICS_URL}"]
  database = "metrics"
  username = "telegraf"
  password = "${METRICS_PASSWORD}"
  skip_database_creation = true
  timeout = "5s"
```

- [ ] **Step 2: linux.conf**

```toml
[[inputs.cpu]]
  percpu = true
  totalcpu = true
  collect_cpu_time = false
  report_active = true

[[inputs.mem]]
[[inputs.swap]]
[[inputs.system]]
[[inputs.kernel]]
[[inputs.processes]]
[[inputs.netstat]]
[[inputs.temp]]

[[inputs.disk]]
  ignore_fs = ["tmpfs", "devtmpfs", "devfs", "iso9660", "overlay", "aufs", "squashfs", "efivarfs"]

# Whole devices only; partitions and dm/zram layers would double-count the same IO.
[[inputs.diskio]]
  devices = ["sd?", "vd?", "xvd?", "nvme?n?", "mmcblk?"]
  skip_serial_number = true

# Container bridges and veth pairs mirror traffic already counted on the uplink.
[[inputs.net]]
  [inputs.net.tagdrop]
    interface = ["lo", "veth*", "br-*", "docker*", "virbr*"]
```

- [ ] **Step 3: nvidia.conf**

```toml
[[inputs.nvidia_smi]]
  timeout = "5s"
  # Per-process rows carry the process name as a tag; not needed on the dashboard.
  namedrop = ["nvidia_smi_process"]
```

- [ ] **Step 4: docker.conf**

```toml
[[inputs.docker]]
  endpoint = "${METRICS_DOCKER_ENDPOINT}"
  perdevice_include = []
  total_include = ["cpu", "blkio", "network"]
  # Compose labels become tags otherwise, one series per label value.
  docker_label_exclude = ["*"]
```

- [ ] **Step 5: telegraf.service** (from the tarball's unit; path and env file changed)

```ini
[Unit]
Description=Telegraf metrics agent (homelab)
Documentation=https://github.com/PawelWywiol/homelab/tree/main/scripts/metrics-agent
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
NotifyAccess=all
EnvironmentFile=/etc/default/telegraf
User=telegraf
ExecStart=/usr/local/bin/telegraf -config /etc/telegraf/telegraf.conf -config-directory /etc/telegraf/telegraf.d
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartForceExitStatus=SIGPIPE
KillMode=mixed
LimitMEMLOCK=8M:8M
PrivateMounts=true

[Install]
WantedBy=multi-user.target
```

- [ ] **Step 6: Validate fragments with the real binary**

```bash
S=$(mktemp -d); cd "$S"
curl -fsSLO https://dl.influxdata.com/telegraf/releases/telegraf-1.40.1_linux_amd64.tar.gz && tar xzf telegraf-*.tar.gz
T=$S/telegraf-1.40.1/usr/bin/telegraf; D=~/code/pawelwywiol/homelab/scripts/metrics-agent/telegraf
export METRICS_URL=http://127.0.0.1:1 METRICS_PASSWORD=x METRICS_INTERVAL=10s METRICS_HOST=test METRICS_OS=arch METRICS_DOCKER_ENDPOINT=unix:///var/run/docker.sock
mkdir d && cp $D/linux.conf $D/nvidia.conf $D/docker.conf d/
$T config check --config $D/base.conf --config-directory d; echo check=$?
$T --config $D/base.conf --config-directory d --test 2>/dev/null | cut -d' ' -f2 | cut -d, -f1 | sort | uniq -c
```

Expected: `check=0`; measurements `cpu disk diskio docker docker_container_* kernel mem net netstat nvidia_smi processes swap system temp`; **no** `nvidia_smi_process`; no `net` line with `interface=veth…`; `diskio` only `nvme0n1`/`nvme1n1`; no `efivarfs` disk. Keep `$T` path for Task 3 (`TELEGRAF_BIN`).

- [ ] **Step 7: List changed files** (no commit).

---

### Task 3: install.sh + tests

**Files:**
- Create: `scripts/metrics-agent/install.sh` (mode 755)
- Create: `scripts/tests/test-metrics-agent.sh` (mode 755)

**Interfaces:**
- Consumes: Task 2 files.
- Produces CLI: `install.sh install [--url URL] [--interval DUR] [--host NAME] [--docker] [--docker-endpoint URL] [--no-docker] [--ref REF]`, `install.sh uninstall`, `install.sh status`. Env: `METRICS_PASSWORD` (input), `METRICS_AGENT_ROOT` (test prefix), `METRICS_AGENT_SKIP_RUNTIME=1` (skip download, user, systemctl, validation).
- Env file `/etc/default/telegraf` (mode 600), fixed key order: `METRICS_URL METRICS_PASSWORD METRICS_INTERVAL METRICS_HOST METRICS_OS METRICS_DOCKER_ENDPOINT`.

- [ ] **Step 1: Write the failing test file**

```bash
#!/bin/bash
# Tests for scripts/metrics-agent/install.sh against a temp root; never touches the host.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
INSTALL="$REPO_ROOT/scripts/metrics-agent/install.sh"
PASS=0; FAIL=0

check() {
    if eval "$2" >/dev/null 2>&1; then echo "PASS: $1"; PASS=$((PASS + 1))
    else echo "FAIL: $1"; FAIL=$((FAIL + 1)); fi
}

run() { METRICS_AGENT_ROOT="$ROOT" METRICS_AGENT_SKIP_RUNTIME=1 bash "$INSTALL" "$@"; }
snapshot() { (cd "$ROOT" && find . -type f -print0 | sort -z | xargs -0 sha256sum); }

ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT

check "shellcheck clean" "shellcheck '$INSTALL'"
check "rejects unknown command" "! run bogus"
check "install without password fails" "! METRICS_PASSWORD= setsid -w env METRICS_AGENT_ROOT='$ROOT' METRICS_AGENT_SKIP_RUNTIME=1 bash '$INSTALL' install --url https://m.example </dev/null"

METRICS_PASSWORD=secret1 run install --url https://m.example --interval 15s --host box >/dev/null
ENV="$ROOT/etc/default/telegraf"
check "env file written"            "[ -f '$ENV' ]"
check "env file mode 600"           "[ \"\$(stat -c %a '$ENV')\" = 600 ]"
check "url stored"                  "grep -qx 'METRICS_URL=https://m.example' '$ENV'"
check "interval stored"             "grep -qx 'METRICS_INTERVAL=15s' '$ENV'"
check "host stored"                 "grep -qx 'METRICS_HOST=box' '$ENV'"
check "base config installed"       "cmp -s '$REPO_ROOT/scripts/metrics-agent/telegraf/base.conf' '$ROOT/etc/telegraf/telegraf.conf'"
check "linux fragment installed"    "[ -f '$ROOT/etc/telegraf/telegraf.d/linux.conf' ]"
check "docker fragment absent"      "[ ! -e '$ROOT/etc/telegraf/telegraf.d/docker.conf' ]"
check "unit installed"              "[ -f '$ROOT/etc/systemd/system/telegraf.service' ]"

before=$(snapshot)
METRICS_PASSWORD= run install >/dev/null
check "re-run keeps settings, tree identical" "[ \"\$(snapshot)\" = '$before' ]"

METRICS_PASSWORD= run install --docker >/dev/null
check "--docker adds fragment"      "[ -f '$ROOT/etc/telegraf/telegraf.d/docker.conf' ]"
check "--docker default endpoint"   "grep -qx 'METRICS_DOCKER_ENDPOINT=unix:///var/run/docker.sock' '$ENV'"
METRICS_PASSWORD= run install >/dev/null
check "docker choice kept"          "[ -f '$ROOT/etc/telegraf/telegraf.d/docker.conf' ]"
METRICS_PASSWORD= run install --no-docker >/dev/null
check "--no-docker removes fragment" "[ ! -e '$ROOT/etc/telegraf/telegraf.d/docker.conf' ]"

run uninstall >/dev/null
check "uninstall leaves no files"   "[ -z \"\$(find '$ROOT' -type f)\" ]"

if [ -n "${TELEGRAF_BIN:-}" ]; then
    D=$(mktemp -d); cp "$REPO_ROOT"/scripts/metrics-agent/telegraf/{linux,nvidia,docker}.conf "$D"/
    check "fragments pass telegraf config check" \
        "METRICS_URL=http://127.0.0.1:1 METRICS_PASSWORD=x METRICS_INTERVAL=10s METRICS_HOST=t METRICS_OS=t METRICS_DOCKER_ENDPOINT=unix:///var/run/docker.sock '$TELEGRAF_BIN' config check --config '$REPO_ROOT/scripts/metrics-agent/telegraf/base.conf' --config-directory '$D'"
    rm -rf "$D"
else
    echo "SKIP: telegraf config check (set TELEGRAF_BIN)"
fi

echo "passed=$PASS failed=$FAIL"
[ "$FAIL" -eq 0 ]
```

- [ ] **Step 2: Run it, expect failures**

Run: `bash scripts/tests/test-metrics-agent.sh`
Expected: FAIL lines (install.sh missing), non-zero exit.

- [ ] **Step 3: Write install.sh**

```bash
#!/usr/bin/env bash
# Telegraf metrics agent for the homelab: install (also updates), uninstall, status.
# Remote: curl -fsSL <raw>/scripts/metrics-agent/install.sh | sudo -E bash -s -- install --url https://metrics.local.wywiol.eu
set -euo pipefail

TELEGRAF_VERSION=1.40.1
INFLUXDATA_FPR=24C975CBA61A024EE1B631787C3D57159FC2F927
INFLUXDATA_KEY_URL=https://repos.influxdata.com/influxdata-archive.key
REPO_RAW=https://raw.githubusercontent.com/PawelWywiol/homelab
DEFAULT_URL=https://metrics.local.wywiol.eu
DEFAULT_DOCKER_ENDPOINT=unix:///var/run/docker.sock

ROOT=${METRICS_AGENT_ROOT:-}
SKIP_RUNTIME=${METRICS_AGENT_SKIP_RUNTIME:-0}
BIN=$ROOT/usr/local/bin/telegraf
CONF_DIR=$ROOT/etc/telegraf
ENV_FILE=$ROOT/etc/default/telegraf
UNIT=$ROOT/etc/systemd/system/telegraf.service

# Empty when piped through curl: BASH_SOURCE is unset, so fragments come from the repo instead.
LOCAL_DIR=""
if [[ -n ${BASH_SOURCE[0]:-} && -f "$(dirname "${BASH_SOURCE[0]}")/telegraf/base.conf" ]]; then
    LOCAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/telegraf"
fi

die() { echo "error: $*" >&2; exit 1; }
log() { echo "==> $*"; }

usage() {
    cat <<EOF
Usage: install.sh install [--url URL] [--interval DUR] [--host NAME]
                          [--docker | --docker-endpoint URL | --no-docker] [--ref REF]
       install.sh uninstall
       install.sh status

Password: METRICS_PASSWORD env var, else the stored one, else a prompt.
Re-running install updates the agent and keeps every setting not given again.
EOF
}

require_platform() {
    [[ $(uname -s) == Linux ]] || die "unsupported OS: $(uname -s) (Linux with systemd only for now)"
    [[ $SKIP_RUNTIME == 1 ]] && return
    [[ $EUID -eq 0 ]] || die "run as root (sudo)"
    command -v systemctl >/dev/null || die "systemd not found"
}

telegraf_arch() {
    case $(uname -m) in
        x86_64) echo amd64 ;;
        aarch64 | arm64) echo arm64 ;;
        armv7l | armv6l) echo armhf ;;
        *) die "unsupported architecture: $(uname -m)" ;;
    esac
}

fetch_fragment() {
    local name=$1 ref=$2 dest=$3
    if [[ -n $LOCAL_DIR ]]; then
        cp "$LOCAL_DIR/$name" "$dest"
    else
        curl -fsSL "$REPO_RAW/$ref/scripts/metrics-agent/telegraf/$name" -o "$dest"
    fi
}

install_binary() {
    if [[ -x $BIN ]] && "$BIN" --version 2>/dev/null | grep -q "Telegraf $TELEGRAF_VERSION "; then
        return
    fi
    local arch tmp file
    arch=$(telegraf_arch)
    tmp=$(mktemp -d)
    file="telegraf-${TELEGRAF_VERSION}_linux_${arch}.tar.gz"
    log "downloading $file"
    curl -fsSL "https://dl.influxdata.com/telegraf/releases/$file" -o "$tmp/$file"
    curl -fsSL "https://dl.influxdata.com/telegraf/releases/$file.asc" -o "$tmp/$file.asc"
    curl -fsSL "$INFLUXDATA_KEY_URL" -o "$tmp/key.asc"
    mkdir -m 700 "$tmp/gnupg"
    GNUPGHOME="$tmp/gnupg" gpg --batch --quiet --import "$tmp/key.asc" 2>/dev/null
    GNUPGHOME="$tmp/gnupg" gpg --batch --status-fd 1 --verify "$tmp/$file.asc" "$tmp/$file" 2>/dev/null |
        grep -q "^\[GNUPG:\] VALIDSIG .* $INFLUXDATA_FPR$" || { rm -rf "$tmp"; die "signature check failed for $file"; }
    tar -xzf "$tmp/$file" -C "$tmp" "telegraf-$TELEGRAF_VERSION/usr/bin/telegraf"
    install -D -m 755 "$tmp/telegraf-$TELEGRAF_VERSION/usr/bin/telegraf" "$BIN"
    rm -rf "$tmp"
}

ensure_user() {
    id telegraf >/dev/null 2>&1 && return
    useradd --system --no-create-home --home-dir /nonexistent --shell "$(command -v nologin)" telegraf
}

read_password() {
    [[ -n $password ]] && return
    # Opening, not -r: without a controlling terminal (setsid, cron) -r is still true but the open fails.
    { true </dev/tty; } 2>/dev/null || die "no password: set METRICS_PASSWORD"
    read -rsp "InfluxDB password for user telegraf: " password </dev/tty
    echo >&2
    [[ -n $password ]] || die "empty password"
}

cmd_install() {
    local url="" interval="" host="" docker_endpoint="" ref=main docker_flag=""
    while [[ $# -gt 0 ]]; do
        case $1 in
            --url) url=$2; shift 2 ;;
            --interval) interval=$2; shift 2 ;;
            --host) host=$2; shift 2 ;;
            --docker) docker_flag=on; shift ;;
            --docker-endpoint) docker_flag=on; docker_endpoint=$2; shift 2 ;;
            --no-docker) docker_flag=off; shift ;;
            --ref) ref=$2; shift 2 ;;
            *) usage; die "unknown option: $1" ;;
        esac
    done
    require_platform

    local METRICS_URL="" METRICS_PASSWORD="" METRICS_INTERVAL="" METRICS_HOST="" METRICS_OS="" METRICS_DOCKER_ENDPOINT=""
    if [[ -f $ENV_FILE ]]; then
        # shellcheck source=/dev/null
        . "$ENV_FILE"
    fi
    url=${url:-${METRICS_URL:-$DEFAULT_URL}}
    interval=${interval:-${METRICS_INTERVAL:-10s}}
    host=${host:-${METRICS_HOST:-$(hostname)}}
    case $docker_flag in
        on) docker_endpoint=${docker_endpoint:-$DEFAULT_DOCKER_ENDPOINT} ;;
        off) docker_endpoint="" ;;
        "") docker_endpoint=$METRICS_DOCKER_ENDPOINT ;;
    esac
    password=${METRICS_PASSWORD_INPUT:-$METRICS_PASSWORD}
    read_password
    local os
    # shellcheck source=/dev/null
    os=$(. /etc/os-release 2>/dev/null; echo "${ID:-linux}")

    local stage
    stage=$(mktemp -d)
    mkdir -p "$stage/telegraf.d"
    fetch_fragment base.conf "$ref" "$stage/telegraf.conf"
    fetch_fragment linux.conf "$ref" "$stage/telegraf.d/linux.conf"
    command -v nvidia-smi >/dev/null && fetch_fragment nvidia.conf "$ref" "$stage/telegraf.d/nvidia.conf"
    [[ -n $docker_endpoint ]] && fetch_fragment docker.conf "$ref" "$stage/telegraf.d/docker.conf"
    fetch_fragment telegraf.service "$ref" "$stage/telegraf.service"
    printf '%s\n' "METRICS_URL=$url" "METRICS_PASSWORD=$password" "METRICS_INTERVAL=$interval" \
        "METRICS_HOST=$host" "METRICS_OS=$os" "METRICS_DOCKER_ENDPOINT=$docker_endpoint" >"$stage/env"

    if [[ $SKIP_RUNTIME != 1 ]]; then
        install_binary
        ensure_user
        log "validating configuration"
        (set -a; . "$stage/env"; "$BIN" --config "$stage/telegraf.conf" --config-directory "$stage/telegraf.d" --test >/dev/null) ||
            { rm -rf "$stage"; die "new configuration rejected by telegraf; previous one left in place"; }
    fi

    mkdir -p "$CONF_DIR" "$(dirname "$ENV_FILE")" "$(dirname "$UNIT")"
    install -m 644 "$stage/telegraf.conf" "$CONF_DIR/telegraf.conf"
    rm -rf "$CONF_DIR/telegraf.d"
    cp -r "$stage/telegraf.d" "$CONF_DIR/telegraf.d"
    chmod 755 "$CONF_DIR/telegraf.d"; chmod 644 "$CONF_DIR"/telegraf.d/*.conf
    install -m 600 "$stage/env" "$ENV_FILE"
    install -m 644 "$stage/telegraf.service" "$UNIT"
    rm -rf "$stage"

    if [[ $SKIP_RUNTIME != 1 ]]; then
        [[ $docker_endpoint == unix://* ]] && getent group docker >/dev/null && usermod -aG docker telegraf
        systemctl daemon-reload
        systemctl enable telegraf >/dev/null 2>&1
        systemctl restart telegraf
        log "telegraf $TELEGRAF_VERSION running as $host → $url every $interval"
    fi
}

cmd_uninstall() {
    require_platform
    if [[ $SKIP_RUNTIME != 1 ]]; then
        systemctl disable --now telegraf >/dev/null 2>&1 || true
    fi
    rm -rf "$BIN" "$CONF_DIR" "$ENV_FILE" "$UNIT"
    if [[ $SKIP_RUNTIME != 1 ]]; then
        systemctl daemon-reload
        id telegraf >/dev/null 2>&1 && userdel telegraf
    fi
    log "telegraf removed"
}

cmd_status() {
    [[ -x $BIN ]] || { echo "not installed"; exit 1; }
    "$BIN" --version
    [[ -r $ENV_FILE ]] && grep -v '^METRICS_PASSWORD=' "$ENV_FILE"
    systemctl status telegraf --no-pager --lines 5
}

password=""
METRICS_PASSWORD_INPUT=${METRICS_PASSWORD:-}
case ${1:-} in
    install) shift; cmd_install "$@" ;;
    uninstall) cmd_uninstall ;;
    status) cmd_status ;;
    -h | --help | "") usage ;;
    *) usage; die "unknown command: $1" ;;
esac
```

Note for the implementer: the env file is sourced with `.`; only root can read it. Values never contain spaces (URL, duration, hostname, hex passwords from Task 7). `METRICS_PASSWORD_INPUT` is captured at startup, before the env file is sourced, so an explicit password wins over the stored one; the `local` declarations keep sourced values out of global scope.

- [ ] **Step 4: Run tests**

Run: `shellcheck scripts/metrics-agent/install.sh && TELEGRAF_BIN=<path from Task 2> bash scripts/tests/test-metrics-agent.sh`
Expected: all `PASS`, `failed=0`, exit 0. Fix install.sh until so (not the tests, unless a test contradicts the spec).

- [ ] **Step 5: List changed files** (no commit).

---

### Task 4: Grafana datasource + dashboard

**Files:**
- Modify: `pve/x202/docker/config/grafana/provisioning/datasources/datasource.yml` (append)
- Modify: `pve/x202/docker/config/grafana/compose.yml` (environment), `.env.example`
- Create: `pve/x202/docker/config/grafana/provisioning/dashboards/system-metrics.json`

**Interfaces:**
- Consumes: Task 1 container `metrics-influxdb`, user `grafana`; Task 2 measurement/field names.
- Produces: datasource uid `metrics-influxdb`; dashboard uid `system-metrics`.

- [ ] **Step 1: Datasource** — append:

```yaml
  - name: metrics-influxdb
    uid: metrics-influxdb
    type: influxdb
    url: http://metrics-influxdb:8086
    isDefault: false
    user: grafana
    jsonData:
      dbName: metrics
      httpMode: GET
    secureJsonData:
      password: $METRICS_INFLUXDB_READ_PASSWORD
```

compose.yml environment: add `- METRICS_INFLUXDB_READ_PASSWORD=${METRICS_INFLUXDB_READ_PASSWORD}`; `.env.example`: add `METRICS_INFLUXDB_READ_PASSWORD=`.

- [ ] **Step 2: Dashboard JSON.** Top level:

```json
{
  "uid": "system-metrics",
  "title": "System Metrics",
  "tags": ["system", "telegraf"],
  "schemaVersion": 39,
  "editable": true,
  "time": {"from": "now-6h", "to": "now"},
  "refresh": "30s",
  "templating": {"list": [{
    "name": "host", "type": "query", "label": "Host",
    "datasource": {"type": "influxdb", "uid": "metrics-influxdb"},
    "query": "SHOW TAG VALUES FROM \"system\" WITH KEY = \"host\"",
    "refresh": 2, "sort": 1, "includeAll": false, "multi": false
  }]},
  "panels": []
}
```

Every target: `{"refId": "A", "rawQuery": true, "resultFormat": "time_series", "query": "<Q>", "alias": "<alias>", "datasource": {"type": "influxdb", "uid": "metrics-influxdb"}}`. `W` below = `"host" =~ /^$host$/ AND $timeFilter`.

Timeseries panel template (every graph):

```json
{"type": "timeseries", "title": "<t>", "gridPos": {"x": 0, "y": 0, "w": 12, "h": 8},
 "datasource": {"type": "influxdb", "uid": "metrics-influxdb"},
 "fieldConfig": {"defaults": {"unit": "<u>", "min": 0, "custom": {"lineWidth": 2, "fillOpacity": 10, "showPoints": "never", "spanNulls": true}}, "overrides": []},
 "options": {"legend": {"displayMode": "table", "placement": "bottom", "calcs": ["min", "max", "mean", "lastNotNull"], "sortBy": "Mean", "sortDesc": true}, "tooltip": {"mode": "multi", "sort": "desc"}},
 "targets": []}
```

Stat panel template (Overview):

```json
{"type": "stat", "title": "<t>", "gridPos": {"x": 0, "y": 1, "w": 4, "h": 4},
 "datasource": {"type": "influxdb", "uid": "metrics-influxdb"},
 "fieldConfig": {"defaults": {"unit": "<u>", "decimals": 1, "thresholds": {"mode": "absolute", "steps": [{"color": "green", "value": null}, {"color": "yellow", "value": <y>}, {"color": "red", "value": <r>}]}}, "overrides": []},
 "options": {"reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": false}, "graphMode": "area", "colorMode": "value", "textMode": "value_and_name"},
 "targets": []}
```

Row panel: `{"type": "row", "title": "<t>", "collapsed": <bool>, "gridPos": {"x": 0, "y": <y>, "w": 24, "h": 1}, "panels": []}` (collapsed rows hold their panels inside `panels`).

Panels (x,y,w,h). Overview row y=0 expanded; stats h=4 w=4.

| # | Row / Panel | Type | x,y,w | Unit | Thresholds y/r | Query (alias) |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | Uptime | stat | 0,1,4 | s | none (single green step; same for every "none") | `SELECT last("uptime") FROM "system" WHERE W` |
| 2 | CPU | stat | 4,1,4 | percent | 70/90 | `SELECT mean("usage_active") FROM "cpu" WHERE W AND "cpu"='cpu-total' GROUP BY time($__interval)` |
| 3 | Load / core | stat | 8,1,4 | none | 0.7/1 | `SELECT mean("load1") / mean("n_cpus") FROM "system" WHERE W GROUP BY time($__interval)` |
| 4 | RAM | stat | 12,1,4 | percent | 80/92 | `SELECT mean("used_percent") FROM "mem" WHERE W GROUP BY time($__interval)` |
| 5 | Swap | stat | 16,1,4 | percent | 50/80 | `SELECT mean("used_percent") FROM "swap" WHERE W GROUP BY time($__interval)` |
| 6 | Disk / | stat | 20,1,4 | percent | 80/90 | `SELECT last("used_percent") FROM "disk" WHERE W AND "path"='/' GROUP BY time($__interval)` |
| 7 | CPU temp | stat | 0,5,4 | celsius | 75/90 | `SELECT max("temp") FROM "temp" WHERE W AND "sensor" =~ /^(coretemp_package_id_0\|k10temp_tctl\|cpu_thermal)$/ GROUP BY time($__interval)` |
| 8 | GPU | stat | 4,5,4 | percent | 70/90 | `SELECT mean("utilization_gpu") FROM "nvidia_smi" WHERE W GROUP BY time($__interval)` |
| 9 | GPU temp | stat | 8,5,4 | celsius | 75/85 | `SELECT max("temperature_gpu") FROM "nvidia_smi" WHERE W GROUP BY time($__interval)` |
| 10 | VRAM | stat | 12,5,4 | percent | 80/92 | `SELECT mean("memory_used") / mean("memory_total") * 100 FROM "nvidia_smi" WHERE W GROUP BY time($__interval)` |
| 11 | Net ↓ | stat | 16,5,4 | Bps | none | `SELECT sum("rx") FROM (SELECT non_negative_derivative(mean("bytes_recv"), 1s) AS "rx" FROM "net" WHERE W GROUP BY time($__interval), "interface") WHERE $timeFilter GROUP BY time($__interval)` (sum of all non-virtual interfaces). Must return one series in Task 4 Step 4; if the subquery is rejected, use the inner query alone with `textMode="value_and_name"` (one value per interface). |
| 12 | Net ↑ | stat | 20,5,4 | Bps | none | as #11 with `bytes_sent` / alias `tx` |
| 13 | row CPU | row | y=9 | | | expanded |
| 14 | CPU usage by mode | ts | 0,10,12 | percent | | stacked (`custom.stacking.mode="normal"`), `max`=100; four targets: `SELECT mean("usage_user") …`, `usage_system`, `usage_iowait`, `usage_steal`, each `FROM "cpu" WHERE W AND "cpu"='cpu-total' GROUP BY time($__interval)`, aliases `user`,`system`,`iowait`,`steal` |
| 15 | CPU per core | ts | 12,10,12 | percent | | `SELECT mean("usage_active") FROM "cpu" WHERE W AND "cpu" != 'cpu-total' GROUP BY time($__interval), "cpu"` alias `$tag_cpu`; legend `placement: right` |
| 16 | Load average | ts | 0,18,12 | none | | `SELECT mean("load1") AS "1m", mean("load5") AS "5m", mean("load15") AS "15m" FROM "system" WHERE W GROUP BY time($__interval)` |
| 17 | Temperatures | ts | 12,18,12 | celsius | | `SELECT max("temp") FROM "temp" WHERE W GROUP BY time($__interval), "sensor"` alias `$tag_sensor`; `min` unset |
| 18 | row Memory | row | y=26 | | | expanded |
| 19 | Memory | ts | 0,27,12 | bytes | | `SELECT mean("used") AS "used", mean("cached") AS "cached", mean("buffered") AS "buffered", mean("available") AS "available" FROM "mem" WHERE W GROUP BY time($__interval)` |
| 20 | Swap | ts | 12,27,12 | bytes | | `SELECT mean("used") AS "used" FROM "swap" WHERE W GROUP BY time($__interval)` |
| 21 | row GPU | row | y=35 | | | expanded |
| 22 | GPU utilization | ts | 0,36,12 | percent | | `SELECT mean("utilization_gpu") AS "gpu", mean("utilization_memory") AS "memory controller" FROM "nvidia_smi" WHERE W GROUP BY time($__interval)`; `max`=100 |
| 23 | VRAM | ts | 12,36,12 | mbytes | | `SELECT mean("memory_used") AS "used", mean("memory_total") AS "total" FROM "nvidia_smi" WHERE W GROUP BY time($__interval)` |
| 24 | GPU temperature | ts | 0,44,8 | celsius | | `SELECT mean("temperature_gpu") AS "gpu" FROM "nvidia_smi" WHERE W GROUP BY time($__interval)` |
| 25 | GPU power | ts | 8,44,8 | watt | | `SELECT mean("power_draw") AS "draw", mean("power_limit") AS "limit" FROM "nvidia_smi" WHERE W GROUP BY time($__interval)` |
| 26 | GPU fan | ts | 16,44,8 | percent | | `SELECT mean("fan_speed") AS "fan" FROM "nvidia_smi" WHERE W GROUP BY time($__interval)` |
| 27 | row Disk | row | y=52 | | | expanded |
| 28 | Filesystem usage | bargauge | 0,53,8 | percent | 80/90 | `SELECT last("used_percent") FROM "disk" WHERE W GROUP BY "path"` alias `$tag_path`; `options.displayMode="gradient"`, `orientation="horizontal"`, `max`=100 |
| 29 | Disk throughput | ts | 8,53,8 | Bps | | `SELECT non_negative_derivative(mean("read_bytes"), 1s) AS "read", non_negative_derivative(mean("write_bytes"), 1s) AS "write" FROM "diskio" WHERE W GROUP BY time($__interval), "name"` alias `$tag_name $col` |
| 30 | Disk IOPS | ts | 16,53,8 | iops | | same shape with `reads`/`writes` |
| 31 | Disk busy | ts | 0,61,24 | percent | | `SELECT non_negative_derivative(mean("io_time"), 1s) / 10 FROM "diskio" WHERE W GROUP BY time($__interval), "name"` alias `$tag_name`; `max`=100 (io_time is ms busy; ms per s / 10 = %) |
| 32 | row Network | row | y=69 | | | expanded |
| 33 | Traffic | ts | 0,70,12 | Bps | | `SELECT non_negative_derivative(mean("bytes_recv"), 1s) AS "rx", non_negative_derivative(mean("bytes_sent"), 1s) AS "tx" FROM "net" WHERE W GROUP BY time($__interval), "interface"` alias `$tag_interface $col`; override by regex `/ tx$/` → `custom.transform = "negative-Y"`, fixed color `blue`; `/ rx$/` → fixed color `green`; `min` unset |
| 34 | Errors & drops | ts | 12,70,12 | pps | | `SELECT non_negative_derivative(mean("err_in"),1s) AS "err in", non_negative_derivative(mean("err_out"),1s) AS "err out", non_negative_derivative(mean("drop_in"),1s) AS "drop in", non_negative_derivative(mean("drop_out"),1s) AS "drop out" FROM "net" WHERE W GROUP BY time($__interval), "interface"` alias `$tag_interface $col` |
| 35 | TCP connections | ts | 0,78,24 | none | | `SELECT mean("tcp_established") AS "established", mean("tcp_time_wait") AS "time_wait", mean("tcp_close_wait") AS "close_wait", mean("tcp_listen") AS "listen" FROM "netstat" WHERE W GROUP BY time($__interval)` |
| 36 | row System | row | y=86 | | | **collapsed**; panels 37-38 inside, y=87 |
| 37 | Processes | ts | 0,87,12 | none | | `SELECT mean("running") AS "running", mean("sleeping") AS "sleeping", mean("blocked") AS "blocked", mean("zombies") AS "zombies" FROM "processes" WHERE W GROUP BY time($__interval)` |
| 38 | Kernel activity | ts | 12,87,12 | ops | | `SELECT non_negative_derivative(mean("context_switches"), 1s) AS "context switches/s", non_negative_derivative(mean("interrupts"), 1s) AS "interrupts/s" FROM "kernel" WHERE W GROUP BY time($__interval)` |
| 39 | row Docker | row | y=95 | | | **collapsed**; panels 40-42 inside, y=96 |
| 40 | Container CPU | ts | 0,96,8 | percent | | `SELECT mean("usage_percent") FROM "docker_container_cpu" WHERE W AND "cpu"='cpu-total' GROUP BY time($__interval), "container_name"` alias `$tag_container_name` |
| 41 | Container memory | ts | 8,96,8 | bytes | | `SELECT mean("usage") FROM "docker_container_mem" WHERE W GROUP BY time($__interval), "container_name"` alias `$tag_container_name` |
| 42 | Container network | ts | 16,96,8 | Bps | | `SELECT non_negative_derivative(mean("rx_bytes"), 1s) AS "rx", non_negative_derivative(mean("tx_bytes"), 1s) AS "tx" FROM "docker_container_net" WHERE W GROUP BY time($__interval), "container_name"` alias `$tag_container_name $col`; same rx/tx overrides as #33 |

Panel `id`s: sequential 1..42 in table order. Replace `W` literally with `"host" =~ /^$host$/ AND $timeFilter` in every query, and add `fill(null)` after every `GROUP BY time(...)` clause list.

- [ ] **Step 3: Add dashboard tests** to `scripts/tests/test-metrics-agent.sh` (before the summary):

```bash
DASH="$REPO_ROOT/pve/x202/docker/config/grafana/provisioning/dashboards/system-metrics.json"
check "dashboard is valid JSON" "jq -e . '$DASH'"
check "dashboard uid" "[ \"\$(jq -r .uid '$DASH')\" = system-metrics ]"
check "every panel uses metrics-influxdb" \
    "[ -z \"\$(jq -r '[.panels[], (.panels[].panels // [])[]] | .[] | select(.type != \"row\") | select(.datasource.uid != \"metrics-influxdb\") | .title' '$DASH')\" ]"
check "queries only use produced measurements" \
    "[ -z \"\$(jq -r '.. | .query? // empty' '$DASH' | grep -oE 'FROM \"[a-z_]+\"' | sort -u | grep -vE '\"(system|cpu|mem|swap|disk|diskio|net|netstat|processes|kernel|temp|nvidia_smi|docker_container_cpu|docker_container_mem|docker_container_net)\"')\" ]"
check "no dangling W placeholder" "! grep -q 'WHERE W' '$DASH'"
```

Run: `bash scripts/tests/test-metrics-agent.sh` → `failed=0`.

- [ ] **Step 4: Local end-to-end preview** (throwaway, on this workstation)

```bash
docker network create mi-net
# metrics-influxdb as in Task 1 Step 5, plus --network mi-net --name metrics-influxdb
docker run -d --rm --name gf-smoke --network mi-net -p 127.0.0.1:13000:3000 \
  -e GF_AUTH_ANONYMOUS_ENABLED=true -e GF_AUTH_ANONYMOUS_ORG_ROLE=Viewer \
  -e METRICS_INFLUXDB_READ_PASSWORD=rpw -e INFLUXDB_TOKEN=x \
  -v "$PWD/pve/x202/docker/config/grafana/provisioning:/etc/grafana/provisioning" grafana/grafana:12.0.0
# telegraf in foreground writing to it for 5 minutes:
METRICS_URL=http://127.0.0.1:18087 METRICS_PASSWORD=wpw METRICS_INTERVAL=10s METRICS_HOST=$(hostname) METRICS_OS=arch \
  METRICS_DOCKER_ENDPOINT=unix:///var/run/docker.sock timeout 300 $TELEGRAF_BIN --config scripts/metrics-agent/telegraf/base.conf --config-directory <dir with linux/nvidia/docker.conf>
curl -s http://127.0.0.1:13000/api/datasources/uid/metrics-influxdb/health
```

Expected: health `"status":"OK"`. Open `http://127.0.0.1:13000/d/system-metrics` in the browser tool, screenshot at 1920×1080, and check: no "No data" panels except Docker row when it is off; stats show values; no overlapping panels; legends show Min/Max/Mean/Last. Fix JSON until clean. Then `docker stop gf-smoke metrics-influxdb; docker network rm mi-net`.

- [ ] **Step 5: List changed files** (no commit).

---

### Task 5: Caddy route and homepage entry

**Files:**
- Modify: `pve/x000/docker/config/caddy/Caddyfile` (after the `@influxdb` block)
- Modify: `pve/x000/docker/config/homepage/config/services.yaml` (after the InfluxDB entry under x202)

- [ ] **Step 1: Caddyfile**

```
    @metrics host metrics.local.wywiol.eu
    handle @metrics {
        reverse_proxy 192.168.0.202:8087
    }
```

- [ ] **Step 2: services.yaml**

```yaml
    - Metrics DB:
        href: https://grafana.local.wywiol.eu/d/system-metrics
        icon: influxdb
        description: Host metrics store (Telegraf)
        server: x202
        container: metrics-influxdb
```

- [ ] **Step 3: Validate** — `docker run --rm -v "$PWD/pve/x000/docker/config/caddy/Caddyfile:/etc/caddy/Caddyfile:ro" caddy:2 caddy adapt --config /etc/caddy/Caddyfile >/dev/null; echo rc=$?`. If the stock image rejects the `dns cloudflare` directive (plugin not built in), instead confirm by diff that the new block matches the `@influxdb` block shape exactly, and state that the adapt check was not possible. `python3 -c 'import yaml,sys;yaml.safe_load(open(sys.argv[1]))' pve/x000/docker/config/homepage/config/services.yaml` → no error.

- [ ] **Step 4: List changed files** (no commit).

---

### Task 6: Documentation

**Files:**
- Create: `scripts/metrics-agent/README.md`
- Modify: `CLAUDE.md` (x202 table: `metrics-influxdb | 8087 | Host metrics store (Telegraf)`; count 13→14; "Host metrics agent" subsection; directory tree `scripts/metrics-agent/`; docs link)
- Modify: `scripts/README.md` (Available Scripts + `## metrics-agent` pointer + Tests entry)
- Modify: `pve/x202/README.md` (Databases: `metrics-influxdb - Host metrics (auth, 90d)`; how to change retention)
- Modify: `docs/README.md` (Monitoring entry)
- Modify: `.claude/docs/gotchas.md`, `.claude/docs/INDEX.md` (entries: Telegraf strict env handling; init-influxdb.sh runs only on empty volume; tarball has only .asc; `influxdb:latest` = 3 Core)

- [ ] **Step 1: scripts/metrics-agent/README.md** sections: What/why (Telegraf, push, InfluxDB 1.13, links to spec); Install one-liner:

```bash
curl -fsSL https://raw.githubusercontent.com/PawelWywiol/homelab/main/scripts/metrics-agent/install.sh -o /tmp/metrics-install.sh
sudo METRICS_PASSWORD='…' bash /tmp/metrics-install.sh install            # defaults: 10s, hostname, no docker
sudo bash /tmp/metrics-install.sh install --interval 30s --docker          # update; password kept
sudo bash /tmp/metrics-install.sh status
sudo bash /tmp/metrics-install.sh uninstall
```

Flags table; files installed table; changing interval by hand (`/etc/default/telegraf` then `systemctl restart telegraf`); retention change command (`ALTER RETENTION POLICY "metrics_rp" ON "metrics" DURATION 180d` via admin); Docker socket = root-equivalent warning; "Verified against" table (Telegraf 1.40.1, InfluxDB 1.13.1, Grafana 12.0.0, Arch/Omarchy kernel from `uname -r`, NVIDIA driver from `nvidia-smi`); measured overhead (filled in Task 7); roadmap (Debian/RPi apt, macOS launchd, Proxmox input, Fleet dashboard, Claude tokens after statusline fix).

- [ ] **Step 2: Apply the other edits** listed above; re-read each file after editing for consistency with CLAUDE.md tables.

- [ ] **Step 3: List changed files** (no commit).

---

### Task 7: Deploy and live verification (needs the user)

- [ ] **Step 1: Pre-checks on x202** — `ssh x202 'ss -ltn | grep -c ":8087 "'` → `0`.
- [ ] **Step 2: Generate secrets locally** — `for k in ADMIN WRITE READ; do echo "METRICS_INFLUXDB_${k}_PASSWORD=$(openssl rand -hex 24)"; done` plus `METRICS_INFLUXDB_ADMIN_USER=admin`, `METRICS_RETENTION=90d`. Hand to the user; they create `pve/x202/docker/config/metrics-influxdb/.env` on x202 and add `METRICS_INFLUXDB_READ_PASSWORD` to grafana's `.env` there.
- [ ] **Step 3: User pushes to `main`**; webhook deploys x202 (`metrics-influxdb`, `grafana`) and x000 (`caddy`, `homepage`). Wait for the ✅ Discord notification.
- [ ] **Step 4: Verify server** — `curl -s -o /dev/null -w '%{http_code}' https://metrics.local.wywiol.eu/ping` → `204`; anonymous `SHOW DATABASES` → `401`; Grafana `/api/datasources/uid/metrics-influxdb/health` → OK.
- [ ] **Step 5: Install on this workstation** — `sudo METRICS_PASSWORD=<write pw> bash scripts/metrics-agent/install.sh install --docker`; `systemctl is-active telegraf` → `active`; `journalctl -u telegraf -n 20` → no `E!`.
- [ ] **Step 6: Data arrives** — as `grafana`: `SHOW MEASUREMENTS` includes all of Task 2's list; `SELECT count("usage_active") FROM "cpu" WHERE "host"='<hostname>' AND time > now() - 5m` → ≈30 per cpu series.
- [ ] **Step 7: Permissions** — telegraf user `SELECT` → not authorized; grafana user write → 403.
- [ ] **Step 8: Overhead** — after 10 min: `ps -o %cpu,rss -C telegraf`, and `systemctl show telegraf -p CPUUsageNSec` read twice 60 s apart → CPU % = Δns / 60e9 × 100. Record in README.
- [ ] **Step 9: Dashboard** — open `https://grafana.local.wywiol.eu/d/system-metrics`, screenshot, confirm every expanded row shows data.
- [ ] **Step 10: Update/uninstall cycle** — re-run install (no flags) → service restarted, env file unchanged (`sha256sum` before/after); `uninstall` → no `/usr/local/bin/telegraf`, `/etc/telegraf`, unit, user; install again → data resumes.
- [ ] **Step 11: Final** — full `bash scripts/tests/test-metrics-agent.sh` and existing suites (`scripts/tests/test-init-host.sh`, `test-sync-makefile.sh`) still pass; propose branch + commit message.

## Self-review notes

- Spec coverage: store (T1), agent + installer + update/uninstall + validation-before-swap (T2–T3), dashboard incl. Overview/CPU/Memory/GPU/Disk/Network/System/Docker + min/max/mean/last legends (T4), Caddy/homepage (T5), docs (T6), live checks 1-7 of spec (T7).
- Known risk: Overview Net ↓/↑ single-number query (panel #11) must be proven in Task 4 Step 4; the fallback is spelled out.
- CPU temp sensor names for AMD (`k10temp_tctl`) and RPi (`cpu_thermal`) are unverified; only `coretemp_package_id_0` is verified on this host. Revisit when those hosts are added.
