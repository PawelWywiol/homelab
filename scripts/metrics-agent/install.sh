#!/usr/bin/env bash
# Telegraf metrics agent for the homelab: install (also updates), uninstall, status.
# Remote: f=$(mktemp); curl -fsSL <raw>/scripts/metrics-agent/install.sh -o "$f"; sudo bash "$f" install
# (prompts for the password on /dev/tty). Unattended: read -rs METRICS_PASSWORD; export METRICS_PASSWORD;
# sudo --preserve-env=METRICS_PASSWORD bash "$f" install
set -euo pipefail

TELEGRAF_VERSION=1.40.1
INFLUXDATA_FPR=24C975CBA61A024EE1B631787C3D57159FC2F927
INFLUXDATA_KEY_URL=https://repos.influxdata.com/influxdata-archive.key
REPO_RAW=https://raw.githubusercontent.com/PawelWywiol/homelab
DEFAULT_URL=https://metrics.local.wywiol.eu
DEFAULT_DOCKER_ENDPOINT=unix:///var/run/docker.sock
# Every stored/typed value ends up in a TOML string, a systemd EnvironmentFile and a shell
# word; this set is safe in all three, so unsafe input is rejected instead of escaped.
VALUE_RE='^[A-Za-z0-9._~:/@+=,-]*$'

ROOT=${METRICS_AGENT_ROOT:-}
SKIP_RUNTIME=${METRICS_AGENT_SKIP_RUNTIME:-0}
BIN=$ROOT/usr/local/bin/telegraf
CONF_DIR=$ROOT/etc/telegraf
ENV_FILE=$ROOT/etc/default/telegraf
UNIT=$ROOT/etc/systemd/system/telegraf.service
password=""
METRICS_PASSWORD_INPUT=${METRICS_PASSWORD:-}

# Staging area for a download/build in progress; cleaned up on any exit (success, error, or
# die) so a rejected install never leaves a plaintext password or a partial binary behind.
stage=""
tmp=""
STAGE_BIN=""
cleanup() {
    # if/fi, not &&: a no-op branch must not turn into a false exit status and clobber $?
    # for the EXIT trap (which becomes the script's own exit code otherwise).
    if [[ -n $stage ]]; then rm -rf "$stage"; fi
    if [[ -n $tmp ]]; then rm -rf "$tmp"; fi
}
trap cleanup EXIT

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
    command -v systemctl >/dev/null || die "systemctl not found"
}

require_download_tools() {
    [[ $SKIP_RUNTIME == 1 ]] && return
    local cmd
    for cmd in curl gpg tar; do
        command -v "$cmd" >/dev/null || die "$cmd not found"
    done
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

validate_value() {
    local name=$1 value=$2
    [[ $value =~ $VALUE_RE ]] || die "invalid value for $name: disallowed characters"
}

# Downloads and GPG-verifies telegraf into $stage (never touching the live $BIN), or reuses
# it unmodified if it is already the right version. Sets STAGE_BIN to the result either way,
# so the caller always validates the exact binary it is about to install.
install_binary() {
    if [[ -x $BIN ]] && "$BIN" --version 2>/dev/null | grep -q "Telegraf $TELEGRAF_VERSION "; then
        STAGE_BIN=$BIN
        return
    fi
    local arch file
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
        grep -q "^\[GNUPG:\] VALIDSIG .* $INFLUXDATA_FPR$" || die "signature check failed for $file"
    tar -xzf "$tmp/$file" -C "$tmp" "telegraf-$TELEGRAF_VERSION/usr/bin/telegraf"
    STAGE_BIN="$stage/telegraf"
    install -D -m 755 "$tmp/telegraf-$TELEGRAF_VERSION/usr/bin/telegraf" "$STAGE_BIN"
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

# Reads back only the six known keys, one assignment per line; never sourced/evaluated, so
# a stray or hostile line in the file (extra "key=value", or no "=" at all) is inert data.
read_env_file() {
    [[ -f $ENV_FILE ]] || return 0
    local key value
    while IFS='=' read -r key value; do
        case $key in
            METRICS_URL) STORED_URL=$value ;;
            METRICS_PASSWORD) STORED_PASSWORD=$value ;;
            METRICS_INTERVAL) STORED_INTERVAL=$value ;;
            METRICS_HOST) STORED_HOST=$value ;;
            METRICS_DOCKER_ENDPOINT) STORED_DOCKER_ENDPOINT=$value ;;
        esac
    done <"$ENV_FILE"
}

cmd_install() {
    local url="" interval="" host="" docker_endpoint="" ref=main docker_flag=""
    while [[ $# -gt 0 ]]; do
        case $1 in
            --url | --interval | --host | --docker-endpoint | --ref)
                [[ $# -ge 2 ]] || die "missing value for $1"
                ;;
        esac
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
    require_download_tools

    local STORED_URL="" STORED_PASSWORD="" STORED_INTERVAL="" STORED_HOST="" STORED_DOCKER_ENDPOINT=""
    read_env_file
    url=${url:-${STORED_URL:-$DEFAULT_URL}}
    interval=${interval:-${STORED_INTERVAL:-10s}}
    host=${host:-${STORED_HOST:-$(hostname)}}
    case $docker_flag in
        on) docker_endpoint=${docker_endpoint:-$DEFAULT_DOCKER_ENDPOINT} ;;
        off) docker_endpoint="" ;;
        "") docker_endpoint=$STORED_DOCKER_ENDPOINT ;;
    esac
    password=${METRICS_PASSWORD_INPUT:-$STORED_PASSWORD}
    read_password
    local os
    # shellcheck source=/dev/null
    os=$(. "$ROOT/etc/os-release" 2>/dev/null; echo "${ID:-linux}")

    validate_value METRICS_URL "$url"
    validate_value METRICS_PASSWORD "$password"
    validate_value METRICS_INTERVAL "$interval"
    validate_value METRICS_HOST "$host"
    validate_value METRICS_DOCKER_ENDPOINT "$docker_endpoint"
    validate_value METRICS_OS "$os"

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
        log "validating configuration"
        (
            export METRICS_URL="$url" METRICS_PASSWORD="$password" METRICS_INTERVAL="$interval" \
                METRICS_HOST="$host" METRICS_OS="$os" METRICS_DOCKER_ENDPOINT="$docker_endpoint"
            "$STAGE_BIN" --config "$stage/telegraf.conf" --config-directory "$stage/telegraf.d" --test >/dev/null
        ) || die "new configuration rejected by telegraf; previous one left in place"
        ensure_user
    fi

    mkdir -p "$CONF_DIR" "$(dirname "$ENV_FILE")" "$(dirname "$UNIT")"
    [[ $SKIP_RUNTIME == 1 || $STAGE_BIN == "$BIN" ]] || install -D -m 755 "$STAGE_BIN" "$BIN"
    install -m 644 "$stage/telegraf.conf" "$CONF_DIR/telegraf.conf"
    # rename() refuses to replace a non-empty directory in one step, so the old telegraf.d
    # (if any) is renamed out of the way first; each rename is still near-instant, unlike
    # the previous rm -rf + cp which left telegraf.d absent for the whole copy.
    rm -rf "$CONF_DIR/telegraf.d.new" "$CONF_DIR/telegraf.d.old"
    cp -r "$stage/telegraf.d" "$CONF_DIR/telegraf.d.new"
    chmod 755 "$CONF_DIR/telegraf.d.new"
    chmod 644 "$CONF_DIR"/telegraf.d.new/*.conf 2>/dev/null || true
    [[ -e $CONF_DIR/telegraf.d ]] && mv -T "$CONF_DIR/telegraf.d" "$CONF_DIR/telegraf.d.old"
    mv -T "$CONF_DIR/telegraf.d.new" "$CONF_DIR/telegraf.d"
    rm -rf "$CONF_DIR/telegraf.d.old"
    install -m 600 "$stage/env" "$ENV_FILE"
    install -m 644 "$stage/telegraf.service" "$UNIT"

    if [[ $SKIP_RUNTIME != 1 ]]; then
        if [[ $docker_endpoint == unix://* ]]; then
            getent group docker >/dev/null && usermod -aG docker telegraf
        else
            # docker group membership is root-equivalent; drop it once Docker collection is off.
            gpasswd -d telegraf docker >/dev/null 2>&1 || true
        fi
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

case ${1:-} in
    install) shift; cmd_install "$@" ;;
    uninstall) cmd_uninstall ;;
    status) cmd_status ;;
    -h | --help | "") usage ;;
    *) usage; die "unknown command: $1" ;;
esac
