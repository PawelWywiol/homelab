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

    # shellcheck disable=SC2034 # METRICS_OS: sourced for parity with the env file's key set, recomputed below
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
        (
            set -a
            # shellcheck source=/dev/null
            . "$stage/env"
            "$BIN" --config "$stage/telegraf.conf" --config-directory "$stage/telegraf.d" --test >/dev/null
        ) || { rm -rf "$stage"; die "new configuration rejected by telegraf; previous one left in place"; }
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
