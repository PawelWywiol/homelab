#!/bin/bash
# Test suite for health-monitor.sh
# Tests CLI flags, output formats, and check functions

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
SCRIPT_UNDER_TEST="$REPO_ROOT/scripts/health-monitor.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Test counters
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0

# =============================================================================
# Test environment setup
# =============================================================================

setup_test_env() {
    echo -e "${YELLOW}Setting up test environment...${NC}"

    export TEST_DIR=$(mktemp -d)
    export TEST_OUTPUT_DIR="$TEST_DIR/output"
    export MOCK_LOG="$TEST_OUTPUT_DIR/mock.log"
    mkdir -p "$TEST_OUTPUT_DIR"

    # Copy script to test directory
    mkdir -p "$TEST_DIR/scripts"
    if [[ -f "$SCRIPT_UNDER_TEST" ]]; then
        cp "$SCRIPT_UNDER_TEST" "$TEST_DIR/scripts/health-monitor.sh"
        chmod +x "$TEST_DIR/scripts/health-monitor.sh"
    fi

    # Create mock /proc/stat for CPU check (Linux simulation)
    mkdir -p "$TEST_DIR/proc"
    cat > "$TEST_DIR/proc/stat" <<'EOF'
cpu  100000 1000 50000 800000 5000 2000 1000 0 0 0
cpu0 25000 250 12500 200000 1250 500 250 0 0 0
EOF

    # Create mock commands directory
    mkdir -p "$TEST_DIR/mocks"

    # Mock grep to intercept /proc/stat reads
    cat > "$TEST_DIR/mocks/grep" <<'MOCKEOF'
#!/bin/bash
if [[ "$*" == *"/proc/stat"* ]]; then
    # Return mock CPU data
    echo "cpu  100000 1000 50000 800000 5000 2000 1000 0 0 0"
else
    /usr/bin/grep "$@"
fi
MOCKEOF
    chmod +x "$TEST_DIR/mocks/grep"

    # Mock sleep to speed up tests
    cat > "$TEST_DIR/mocks/sleep" <<'MOCKEOF'
#!/bin/bash
# Skip sleep in tests
exit 0
MOCKEOF
    chmod +x "$TEST_DIR/mocks/sleep"

    # Mock uname to report Linux
    cat > "$TEST_DIR/mocks/uname" <<'MOCKEOF'
#!/bin/bash
echo "Linux"
MOCKEOF
    chmod +x "$TEST_DIR/mocks/uname"

    # Set environment variable for /proc/stat path override
    export PROC_STAT_PATH="$TEST_DIR/proc/stat"

    # Mock docker - simulates running containers
    cat > "$TEST_DIR/mocks/docker" <<'MOCKEOF'
#!/bin/bash
echo "DOCKER: $@" >> "$MOCK_LOG"

case "$1" in
    info)
        echo "Containers: 5"
        exit 0
        ;;
    ps)
        if [[ "$*" == *"--format"* ]]; then
            if [[ "$*" == *"-a"* ]]; then
                echo -e "abc123\tcontainer1\trunning\tUp 2 hours\tnginx:latest"
                echo -e "def456\tcontainer2\trunning\tUp 1 day\tredis:7"
                echo -e "ghi789\tcontainer3\texited\tExited (1) 2 hours ago\tpostgres:15"
            else
                echo -e "abc123\tcontainer1\tnginx:latest"
                echo -e "def456\tcontainer2\tredis:7"
            fi
        fi
        exit 0
        ;;
    stats)
        echo -e "abc123\tcontainer1\t5.00%\t2.50%\t100MiB / 1GiB"
        echo -e "def456\tcontainer2\t85.00%\t75.00%\t500MiB / 1GiB"
        exit 0
        ;;
    inspect)
        case "$3" in
            *Privileged*) echo "false" ;;
            *CapAdd*) echo "[]" ;;
            *PidMode*) echo "" ;;
            *NetworkMode*) echo "bridge" ;;
            *Mounts*) echo "" ;;
            *Memory*) echo "1073741824" ;;
            *NanoCpus*) echo "1000000000" ;;
            *RestartCount*) echo "0" ;;
            *ExitCode*) echo "0" ;;
            *StartedAt*) echo "2025-12-01T00:00:00Z" ;;
            *Image*) echo "sha256:abc123def456" ;;
            *Created*) echo "2025-12-01T00:00:00Z" ;;
            *) echo "unknown" ;;
        esac
        exit 0
        ;;
    logs)
        echo "INFO: Container started"
        echo "ERROR: Connection failed"
        exit 0
        ;;
    system)
        echo "10GB"
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
MOCKEOF
    chmod +x "$TEST_DIR/mocks/docker"

    # Mock free - memory info
    cat > "$TEST_DIR/mocks/free" <<'MOCKEOF'
#!/bin/bash
echo "MEMORY: $@" >> "$MOCK_LOG"
echo "              total        used        free      shared  buff/cache   available"
echo "Mem:          16000        8000        2000         500        6000        7500"
echo "Swap:          2000         100        1900"
exit 0
MOCKEOF
    chmod +x "$TEST_DIR/mocks/free"

    # Mock top - CPU info
    cat > "$TEST_DIR/mocks/top" <<'MOCKEOF'
#!/bin/bash
echo "TOP: $@" >> "$MOCK_LOG"
echo "top - 12:00:00 up 1 day, 12:00,  1 user,  load average: 0.50, 0.40, 0.35"
echo "Tasks: 100 total,   1 running,  99 sleeping,   0 stopped,   0 zombie"
echo "%Cpu(s): 25.0 us, 10.0 sy,  0.0 ni, 65.0 id,  0.0 wa,  0.0 hi,  0.0 si,  0.0 st"
exit 0
MOCKEOF
    chmod +x "$TEST_DIR/mocks/top"

    # Mock df - disk info
    cat > "$TEST_DIR/mocks/df" <<'MOCKEOF'
#!/bin/bash
echo "DISK: $@" >> "$MOCK_LOG"
echo "/dev/sda1 100G 50G 50G 50% /"
echo "/dev/sdb1 500G 400G 100G 80% /data"
exit 0
MOCKEOF
    chmod +x "$TEST_DIR/mocks/df"

    # Mock ping - network check
    cat > "$TEST_DIR/mocks/ping" <<'MOCKEOF'
#!/bin/bash
echo "PING: $@" >> "$MOCK_LOG"
exit 0
MOCKEOF
    chmod +x "$TEST_DIR/mocks/ping"

    # Mock journalctl - system logs
    cat > "$TEST_DIR/mocks/journalctl" <<'MOCKEOF'
#!/bin/bash
echo "JOURNAL: $@" >> "$MOCK_LOG"
if [[ "$*" == *"-p err"* ]]; then
    echo "Jan 01 12:00:00 host kernel: ERROR something happened"
    echo "Jan 01 12:01:00 host systemd: Failed to start service"
fi
exit 0
MOCKEOF
    chmod +x "$TEST_DIR/mocks/journalctl"

    # Mock hostname
    cat > "$TEST_DIR/mocks/hostname" <<'MOCKEOF'
#!/bin/bash
if [[ "$1" == "-I" ]]; then
    echo "192.168.1.100"
else
    echo "test-server"
fi
exit 0
MOCKEOF
    chmod +x "$TEST_DIR/mocks/hostname"

    # Mock date
    cat > "$TEST_DIR/mocks/date" <<'MOCKEOF'
#!/bin/bash
if [[ "$*" == *"+%s"* ]]; then
    echo "1704067200"
elif [[ "$*" == *"+%Y-%m-%dT%H:%M:%SZ"* ]]; then
    echo "2026-01-01T12:00:00Z"
elif [[ "$*" == *"-d"* ]]; then
    echo "1704067200"
else
    echo "Mon Jan 1 12:00:00 UTC 2026"
fi
exit 0
MOCKEOF
    chmod +x "$TEST_DIR/mocks/date"

    echo -e "${GREEN}Test environment ready at $TEST_DIR${NC}"
}

cleanup_test_env() {
    if [[ -d "$TEST_DIR" ]]; then
        rm -rf "$TEST_DIR"
    fi
}

reset_log() {
    : > "$MOCK_LOG"
}

# =============================================================================
# Test runner
# =============================================================================

run_test() {
    local test_name=$1
    local test_cmd=$2
    local expected_pattern=$3
    local should_fail=${4:-false}
    local check_output=${5:-false}

    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    reset_log

    echo -n "Test $TESTS_TOTAL: $test_name ... "

    cd "$TEST_DIR"

    local cmd_output=$(mktemp)

    if [ "$should_fail" = true ]; then
        if eval "$test_cmd" &>"$cmd_output"; then
            echo -e "${RED}FAIL${NC} (expected to fail but succeeded)"
            TESTS_FAILED=$((TESTS_FAILED + 1))
        elif grep -qE -- "$expected_pattern" "$cmd_output" 2>/dev/null; then
            echo -e "${GREEN}PASS${NC}"
            TESTS_PASSED=$((TESTS_PASSED + 1))
        else
            echo -e "${RED}FAIL${NC} (wrong error message)"
            echo "Expected pattern: $expected_pattern"
            echo "Got:"
            head -20 "$cmd_output"
            TESTS_FAILED=$((TESTS_FAILED + 1))
        fi
    elif [ "$check_output" = true ]; then
        if eval "$test_cmd" &>"$cmd_output"; then
            if grep -qE -- "$expected_pattern" "$cmd_output" 2>/dev/null; then
                echo -e "${GREEN}PASS${NC}"
                TESTS_PASSED=$((TESTS_PASSED + 1))
            else
                echo -e "${RED}FAIL${NC} (expected pattern not found in output)"
                echo "Expected: $expected_pattern"
                echo "Output:"
                head -50 "$cmd_output"
                TESTS_FAILED=$((TESTS_FAILED + 1))
            fi
        else
            echo -e "${RED}FAIL${NC} (command failed)"
            echo "Output:"
            head -20 "$cmd_output"
            TESTS_FAILED=$((TESTS_FAILED + 1))
        fi
    else
        if eval "$test_cmd" &>"$cmd_output"; then
            if grep -qE -- "$expected_pattern" "$MOCK_LOG" 2>/dev/null; then
                echo -e "${GREEN}PASS${NC}"
                TESTS_PASSED=$((TESTS_PASSED + 1))
            else
                echo -e "${RED}FAIL${NC} (expected pattern not found in mock log)"
                echo "Expected: $expected_pattern"
                echo "Mock log:"
                cat "$MOCK_LOG" 2>/dev/null || echo "(empty)"
                echo "Command output:"
                head -20 "$cmd_output"
                TESTS_FAILED=$((TESTS_FAILED + 1))
            fi
        else
            echo -e "${RED}FAIL${NC} (command failed)"
            echo "Output:"
            head -20 "$cmd_output"
            TESTS_FAILED=$((TESTS_FAILED + 1))
        fi
    fi
    rm -f "$cmd_output"
}

# =============================================================================
# Test suite
# =============================================================================

echo -e "${YELLOW}=== health-monitor.sh Test Suite ===${NC}\n"

# Check if script exists
if [[ ! -f "$SCRIPT_UNDER_TEST" ]]; then
    echo -e "${RED}ERROR: Script not found at $SCRIPT_UNDER_TEST${NC}"
    echo "Please create the script first."
    exit 1
fi

# Validate script syntax
echo -e "${YELLOW}Validating script syntax...${NC}"
if ! bash -n "$SCRIPT_UNDER_TEST"; then
    echo -e "${RED}ERROR: Script has syntax errors${NC}"
    exit 1
fi
echo -e "${GREEN}Syntax OK${NC}\n"

setup_test_env
trap cleanup_test_env EXIT

# Override PATH to use mocks
export PATH="$TEST_DIR/mocks:$PATH"

# =============================================================================
echo -e "\n${YELLOW}=== CLI Flag Tests ===${NC}"
# =============================================================================

run_test "--help shows usage" \
    "./scripts/health-monitor.sh --help" \
    "USAGE:" \
    false true

run_test "--help shows --format option" \
    "./scripts/health-monitor.sh --help" \
    "--format" \
    false true

run_test "--help shows --output option" \
    "./scripts/health-monitor.sh --help" \
    "--output" \
    false true

run_test "--help shows --quiet option" \
    "./scripts/health-monitor.sh --help" \
    "--quiet" \
    false true

run_test "--help shows --config option" \
    "./scripts/health-monitor.sh --help" \
    "--config" \
    false true

run_test "unknown flag shows error" \
    "./scripts/health-monitor.sh --unknown-flag" \
    "Unknown option" \
    true

run_test "invalid format shows error" \
    "./scripts/health-monitor.sh --format invalid" \
    "Invalid format" \
    true

# =============================================================================
echo -e "\n${YELLOW}=== JSON Output Tests ===${NC}"
# =============================================================================

run_test "JSON output contains report_metadata" \
    "./scripts/health-monitor.sh --quiet --format json" \
    '"report_metadata"' \
    false true

run_test "JSON output contains overall_status" \
    "./scripts/health-monitor.sh --quiet --format json" \
    '"overall_status"' \
    false true

run_test "JSON output contains summary" \
    "./scripts/health-monitor.sh --quiet --format json" \
    '"summary"' \
    false true

run_test "JSON output contains checks section" \
    "./scripts/health-monitor.sh --quiet --format json" \
    '"checks"' \
    false true

run_test "JSON output contains recommendations" \
    "./scripts/health-monitor.sh --quiet --format json" \
    '"recommendations"' \
    false true

run_test "JSON output contains cpu check" \
    "./scripts/health-monitor.sh --quiet --format json" \
    '"cpu"' \
    false true

run_test "JSON output contains memory check" \
    "./scripts/health-monitor.sh --quiet --format json" \
    '"memory"' \
    false true

run_test "JSON output contains docker section" \
    "./scripts/health-monitor.sh --quiet --format json" \
    '"docker"' \
    false true

# =============================================================================
echo -e "\n${YELLOW}=== YAML Output Tests ===${NC}"
# =============================================================================

run_test "YAML output starts with ---" \
    "./scripts/health-monitor.sh --quiet --format yaml" \
    "^---" \
    false true

run_test "YAML output contains report_metadata" \
    "./scripts/health-monitor.sh --quiet --format yaml" \
    "report_metadata" \
    false true

run_test "YAML output contains overall_status" \
    "./scripts/health-monitor.sh --quiet --format yaml" \
    "overall_status" \
    false true

# =============================================================================
echo -e "\n${YELLOW}=== Markdown Output Tests ===${NC}"
# =============================================================================

run_test "Markdown output contains Health Report header" \
    "./scripts/health-monitor.sh --quiet --format markdown" \
    "# Health Report" \
    false true

run_test "Markdown output contains Metadata section" \
    "./scripts/health-monitor.sh --quiet --format markdown" \
    "## Metadata" \
    false true

run_test "Markdown output contains Overall Status" \
    "./scripts/health-monitor.sh --quiet --format markdown" \
    "## Overall Status" \
    false true

run_test "Markdown output contains Summary table" \
    "./scripts/health-monitor.sh --quiet --format markdown" \
    "### Summary" \
    false true

run_test "Markdown output contains System Checks section" \
    "./scripts/health-monitor.sh --quiet --format markdown" \
    "## System Checks" \
    false true

run_test "Markdown output contains Docker section" \
    "./scripts/health-monitor.sh --quiet --format markdown" \
    "## Docker" \
    false true

run_test "Markdown output contains Recommendations section" \
    "./scripts/health-monitor.sh --quiet --format markdown" \
    "## Recommendations" \
    false true

# =============================================================================
echo -e "\n${YELLOW}=== Markdown Parity Tests ===${NC}"
# =============================================================================

run_test "Markdown contains Disk Details section" \
    "./scripts/health-monitor.sh --quiet --format markdown" \
    "#### Disk Details" \
    false true

run_test "Markdown contains Network Connectivity Details" \
    "./scripts/health-monitor.sh --quiet --format markdown" \
    "#### Connectivity Details" \
    false true

run_test "Markdown contains Log Errors section" \
    "./scripts/health-monitor.sh --quiet --format markdown" \
    "#### Log Errors" \
    false true

run_test "Markdown contains Systemd Services section" \
    "./scripts/health-monitor.sh --quiet --format markdown" \
    "### Systemd Services" \
    false true

run_test "Markdown contains Container List section" \
    "./scripts/health-monitor.sh --quiet --format markdown" \
    "#### Container List" \
    false true

run_test "Markdown contains Exited Container Issues section" \
    "./scripts/health-monitor.sh --quiet --format markdown" \
    "### Exited Container Issues" \
    false true

run_test "Markdown contains Container Resources section" \
    "./scripts/health-monitor.sh --quiet --format markdown" \
    "### Container Resources" \
    false true

run_test "Markdown contains Container Restarts section" \
    "./scripts/health-monitor.sh --quiet --format markdown" \
    "### Container Restarts" \
    false true

run_test "Markdown contains Created But Not Running section" \
    "./scripts/health-monitor.sh --quiet --format markdown" \
    "### Created But Not Running" \
    false true

run_test "Markdown contains Stopped But Not Removed section" \
    "./scripts/health-monitor.sh --quiet --format markdown" \
    "### Stopped But Not Removed" \
    false true

run_test "Markdown contains Container Disk Usage section" \
    "./scripts/health-monitor.sh --quiet --format markdown" \
    "### Container Disk Usage" \
    false true

run_test "Markdown contains Long Running Containers section" \
    "./scripts/health-monitor.sh --quiet --format markdown" \
    "### Long Running Containers" \
    false true

run_test "Markdown contains Container Images section" \
    "./scripts/health-monitor.sh --quiet --format markdown" \
    "### Container Images" \
    false true

run_test "Markdown contains Container Logs section" \
    "./scripts/health-monitor.sh --quiet --format markdown" \
    "### Container Logs" \
    false true

run_test "Markdown contains Security Issues section" \
    "./scripts/health-monitor.sh --quiet --format markdown" \
    "### Security Issues" \
    false true

run_test "Markdown contains Resource Limits section" \
    "./scripts/health-monitor.sh --quiet --format markdown" \
    "### Resource Limits" \
    false true

run_test "Markdown contains Network Configuration section" \
    "./scripts/health-monitor.sh --quiet --format markdown" \
    "### Network Configuration" \
    false true

run_test "Markdown contains Volume Mounts section" \
    "./scripts/health-monitor.sh --quiet --format markdown" \
    "### Volume Mounts" \
    false true

run_test "Markdown contains Network Traffic section" \
    "./scripts/health-monitor.sh --quiet --format markdown" \
    "### Network Traffic" \
    false true

run_test "Markdown contains memory threshold" \
    "./scripts/health-monitor.sh --quiet --format markdown" \
    "Threshold.*%$" \
    false true

run_test "Markdown contains script version" \
    "./scripts/health-monitor.sh --quiet --format markdown" \
    "Script Version" \
    false true

# =============================================================================
echo -e "\n${YELLOW}=== Output File Tests ===${NC}"
# =============================================================================

run_test "--output writes to file" \
    "./scripts/health-monitor.sh --quiet --output $TEST_OUTPUT_DIR/report.json && test -f $TEST_OUTPUT_DIR/report.json && echo exists" \
    "exists" \
    false true

run_test "output file contains valid JSON" \
    "./scripts/health-monitor.sh --quiet --output $TEST_OUTPUT_DIR/report2.json && cat $TEST_OUTPUT_DIR/report2.json" \
    '"report_metadata"' \
    false true

# =============================================================================
echo -e "\n${YELLOW}=== Script Structure Tests ===${NC}"
# =============================================================================

run_test "script has check_cpu function" \
    "grep -q 'check_cpu()' ./scripts/health-monitor.sh && echo found" \
    "found" \
    false true

run_test "script has check_memory function" \
    "grep -q 'check_memory()' ./scripts/health-monitor.sh && echo found" \
    "found" \
    false true

run_test "script has check_disk function" \
    "grep -q 'check_disk()' ./scripts/health-monitor.sh && echo found" \
    "found" \
    false true

run_test "script has check_network function" \
    "grep -q 'check_network()' ./scripts/health-monitor.sh && echo found" \
    "found" \
    false true

run_test "script has check_docker_daemon function" \
    "grep -q 'check_docker_daemon()' ./scripts/health-monitor.sh && echo found" \
    "found" \
    false true

run_test "script has check_containers_status function" \
    "grep -q 'check_containers_status()' ./scripts/health-monitor.sh && echo found" \
    "found" \
    false true

run_test "script has check_security_issues function" \
    "grep -q 'check_security_issues()' ./scripts/health-monitor.sh && echo found" \
    "found" \
    false true

run_test "script has check_resource_limits function" \
    "grep -q 'check_resource_limits()' ./scripts/health-monitor.sh && echo found" \
    "found" \
    false true

run_test "script has generate_json_report function" \
    "grep -q 'generate_json_report()' ./scripts/health-monitor.sh && echo found" \
    "found" \
    false true

run_test "script has generate_yaml_report function" \
    "grep -q 'generate_yaml_report()' ./scripts/health-monitor.sh && echo found" \
    "found" \
    false true

run_test "script has generate_markdown_report function" \
    "grep -q 'generate_markdown_report()' ./scripts/health-monitor.sh && echo found" \
    "found" \
    false true

# =============================================================================
echo -e "\n${YELLOW}=== Configuration Tests ===${NC}"
# =============================================================================

# Create test config
cat > "$TEST_DIR/scripts/.env.health-monitor" <<'EOF'
CPU_THRESHOLD=90
MEMORY_THRESHOLD=90
EOF

run_test "loads custom thresholds from config" \
    "./scripts/health-monitor.sh --quiet --format json" \
    '"threshold": 90' \
    false true

rm -f "$TEST_DIR/scripts/.env.health-monitor"

# Test custom config file
cat > "$TEST_DIR/custom-config.env" <<'EOF'
CPU_THRESHOLD=75
EOF

run_test "--config loads custom file" \
    "./scripts/health-monitor.sh --quiet --format json --config $TEST_DIR/custom-config.env" \
    '"threshold": 75' \
    false true

run_test "--config with missing file shows error" \
    "./scripts/health-monitor.sh --config /nonexistent/file" \
    "Config file not found" \
    true

# =============================================================================
echo -e "\n${YELLOW}=== Docker Not Installed Tests ===${NC}"
# =============================================================================

# Test docker not installed scenario
# Create a clean mocks directory without docker
mkdir -p "$TEST_DIR/mocks_nodocker"
for f in "$TEST_DIR/mocks"/*; do
    [[ "$(basename "$f")" != "docker" ]] && cp "$f" "$TEST_DIR/mocks_nodocker/" 2>/dev/null || true
done

# Add essential system commands as passthroughs
for cmd in bash grep awk cat sed tr cut head tail wc date; do
    if ! [[ -f "$TEST_DIR/mocks_nodocker/$cmd" ]]; then
        real_cmd=$(which "$cmd" 2>/dev/null || echo "/usr/bin/$cmd")
        ln -sf "$real_cmd" "$TEST_DIR/mocks_nodocker/$cmd" 2>/dev/null || true
    fi
done

# Use isolated PATH without docker
SAVE_PATH="$PATH"
export PATH="$TEST_DIR/mocks_nodocker:/usr/bin:/bin"

run_test "handles docker not installed" \
    "./scripts/health-monitor.sh --quiet --format json" \
    '"installed": false' \
    false true

# Restore PATH
export PATH="$SAVE_PATH"

# =============================================================================
echo -e "\n${YELLOW}=== Report Metadata Tests ===${NC}"
# =============================================================================

run_test "JSON report contains server_name" \
    "./scripts/health-monitor.sh --quiet --format json" \
    '"server_name"' \
    false true

run_test "JSON report contains server_ip" \
    "./scripts/health-monitor.sh --quiet --format json" \
    '"server_ip"' \
    false true

run_test "JSON report contains generated_at timestamp" \
    "./scripts/health-monitor.sh --quiet --format json" \
    '"generated_at"' \
    false true

run_test "JSON report contains reporting_period_hours" \
    "./scripts/health-monitor.sh --quiet --format json" \
    '"reporting_period_hours"' \
    false true

# =============================================================================
# Summary
# =============================================================================

echo -e "\n${YELLOW}=== Test Summary ===${NC}"
echo "Total tests: $TESTS_TOTAL"
echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed: ${RED}$TESTS_FAILED${NC}"

if [[ $TESTS_FAILED -gt 0 ]]; then
    echo -e "\n${RED}Some tests failed!${NC}"
    exit 1
else
    echo -e "\n${GREEN}All tests passed!${NC}"
    exit 0
fi
