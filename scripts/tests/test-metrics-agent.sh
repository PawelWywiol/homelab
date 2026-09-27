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
