#!/bin/bash
# Test suite for sync-files.sh and root Makefile sync commands

set -e

# Get script location and repo root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Test counters
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0

setup_test_env() {
    echo -e "${YELLOW}Setting up test environment...${NC}"

    export TEST_DIR=$(mktemp -d)
    export TEST_OUTPUT_DIR="$TEST_DIR/output"
    mkdir -p "$TEST_OUTPUT_DIR"

    # Create mock pve structure with .envrc files
    mkdir -p "$TEST_DIR/pve/x202"
    mkdir -p "$TEST_DIR/pve/x201"
    mkdir -p "$TEST_DIR/pve/x250"
    mkdir -p "$TEST_DIR/pve/nohost"

    # x202: valid .envrc with REMOTE_HOST and REMOTE_FILES
    cat > "$TEST_DIR/pve/x202/.envrc" <<'EOF'
REMOTE_HOST="code@x202"
REMOTE_FILES=(
  ".env"
  "docker/config"
)
EOF

    # x201: valid .envrc with different user
    cat > "$TEST_DIR/pve/x201/.envrc" <<'EOF'
REMOTE_HOST="admin@x201"
REMOTE_FILES=(
  "config"
)
EOF

    # x250: valid .envrc
    cat > "$TEST_DIR/pve/x250/.envrc" <<'EOF'
REMOTE_HOST="user@x250"
REMOTE_FILES=(
  "data"
)
EOF

    # nohost: .envrc with empty REMOTE_HOST
    cat > "$TEST_DIR/pve/nohost/.envrc" <<'EOF'
REMOTE_HOST=""
REMOTE_FILES=(
  "files"
)
EOF

    # pathabs: .envrc with absolute path
    mkdir -p "$TEST_DIR/pve/pathabs"
    cat > "$TEST_DIR/pve/pathabs/.envrc" <<'EOF'
REMOTE_HOST="code@server:/opt/data/"
REMOTE_FILES=(
  "config"
)
EOF

    # pathrel: .envrc with home-relative path
    mkdir -p "$TEST_DIR/pve/pathrel"
    cat > "$TEST_DIR/pve/pathrel/.envrc" <<'EOF'
REMOTE_HOST="code@server:~/projects/"
REMOTE_FILES=(
  "app"
)
EOF

    # pathempty: .envrc with empty path after colon
    mkdir -p "$TEST_DIR/pve/pathempty"
    cat > "$TEST_DIR/pve/pathempty/.envrc" <<'EOF'
REMOTE_HOST="code@server:"
REMOTE_FILES=(
  "data"
)
EOF

    # Copy sync-files.sh to test directory (real script, mocked rsync)
    mkdir -p "$TEST_DIR/scripts"
    cp "$REPO_ROOT/scripts/sync-files.sh" "$TEST_DIR/scripts/sync-files.sh"
    chmod +x "$TEST_DIR/scripts/sync-files.sh"

    # Create mock rsync that logs calls
    cat > "$TEST_DIR/mock-rsync" <<'EOF'
#!/bin/bash
echo "RSYNC: $@" >> "$TEST_OUTPUT_DIR/sync.log"
exit 0
EOF
    chmod +x "$TEST_DIR/mock-rsync"

    # Copy Makefile to test directory
    if [ -f "$REPO_ROOT/Makefile" ]; then
        cp "$REPO_ROOT/Makefile" "$TEST_DIR/Makefile"
    else
        echo -e "${RED}ERROR: Makefile not found at $REPO_ROOT/Makefile${NC}"
        exit 1
    fi

    echo -e "${GREEN}Test environment ready at: $TEST_DIR${NC}"
}

cleanup_test_env() {
    echo -e "${YELLOW}Cleaning up test environment...${NC}"
    rm -rf "$TEST_DIR"
}

reset_log() {
    rm -f "$TEST_OUTPUT_DIR/sync.log"
    touch "$TEST_OUTPUT_DIR/sync.log"
}

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

    if [ "$should_fail" = true ]; then
        # Command should fail
        local cmd_output=$(mktemp)
        if $test_cmd &>"$cmd_output"; then
            echo -e "${RED}FAIL${NC} (expected to fail but succeeded)"
            TESTS_FAILED=$((TESTS_FAILED + 1))
        elif grep -q "$expected_pattern" "$cmd_output" 2>/dev/null; then
            echo -e "${GREEN}PASS${NC}"
            TESTS_PASSED=$((TESTS_PASSED + 1))
        else
            echo -e "${RED}FAIL${NC} (wrong error message)"
            echo "Expected pattern: $expected_pattern"
            echo "Got:"
            cat "$cmd_output"
            TESTS_FAILED=$((TESTS_FAILED + 1))
        fi
        rm -f "$cmd_output"
    elif [ "$check_output" = true ]; then
        # Check command output directly
        local cmd_output=$(mktemp)
        if $test_cmd &>"$cmd_output"; then
            if grep -q "$expected_pattern" "$cmd_output" 2>/dev/null; then
                echo -e "${GREEN}PASS${NC}"
                TESTS_PASSED=$((TESTS_PASSED + 1))
            else
                echo -e "${RED}FAIL${NC} (expected pattern not found in output)"
                echo "Expected: $expected_pattern"
                echo "Output:"
                cat "$cmd_output"
                TESTS_FAILED=$((TESTS_FAILED + 1))
            fi
        else
            echo -e "${RED}FAIL${NC} (command failed)"
            echo "Output:"
            cat "$cmd_output"
            TESTS_FAILED=$((TESTS_FAILED + 1))
        fi
        rm -f "$cmd_output"
    else
        # Command should succeed
        local cmd_output=$(mktemp)
        if $test_cmd &>"$cmd_output"; then
            # Check log for expected pattern
            if grep -q "$expected_pattern" "$TEST_OUTPUT_DIR/sync.log" 2>/dev/null; then
                echo -e "${GREEN}PASS${NC}"
                TESTS_PASSED=$((TESTS_PASSED + 1))
            else
                echo -e "${RED}FAIL${NC} (expected pattern not found in log)"
                echo "Expected: $expected_pattern"
                echo "Log contents:"
                cat "$TEST_OUTPUT_DIR/sync.log" 2>/dev/null || echo "(empty)"
                echo "Command output:"
                cat "$cmd_output"
                TESTS_FAILED=$((TESTS_FAILED + 1))
            fi
        else
            echo -e "${RED}FAIL${NC} (command failed)"
            echo "Output:"
            cat "$cmd_output"
            TESTS_FAILED=$((TESTS_FAILED + 1))
        fi
        rm -f "$cmd_output"
    fi
}

# Test suite
echo -e "${YELLOW}=== Sync Script & Makefile Test Suite ===${NC}\n"

setup_test_env

# Override rsync with mock
export PATH="$TEST_DIR:$PATH"
ln -sf "$TEST_DIR/mock-rsync" "$TEST_DIR/rsync"

echo -e "\n${YELLOW}=== sync-files.sh Direct Tests ===${NC}"

# Test 1: pull with valid name
run_test "sync-files.sh pull x202" \
    "./scripts/sync-files.sh pull x202" \
    "code@x202"

# Test 2: push with valid name
run_test "sync-files.sh push x202" \
    "./scripts/sync-files.sh push x202" \
    "code@x202"

# Test 3: error when .envrc missing
run_test "sync-files.sh with missing .envrc" \
    "./scripts/sync-files.sh pull nonexistent" \
    "not found" \
    true

# Test 4: error when REMOTE_HOST empty
run_test "sync-files.sh with empty REMOTE_HOST" \
    "./scripts/sync-files.sh pull nohost" \
    "REMOTE_HOST.*empty\|not set" \
    true

# Test 5: error without arguments
run_test "sync-files.sh without arguments" \
    "./scripts/sync-files.sh" \
    "Usage:" \
    true

# Test 6: error with only one argument
run_test "sync-files.sh with only action" \
    "./scripts/sync-files.sh pull" \
    "Usage:" \
    true

echo -e "\n${YELLOW}=== Makefile Pull Commands ===${NC}"

# Test 7: make pull with valid name
run_test "make pull x202" \
    "make pull x202" \
    "code@x202"

# Test 8: make pull with another valid name
run_test "make pull x201" \
    "make pull x201" \
    "admin@x201"

echo -e "\n${YELLOW}=== Makefile Push Commands ===${NC}"

# Test 9: make push with valid name
run_test "make push x202" \
    "make push x202" \
    "code@x202"

# Test 10: make push with another valid name
run_test "make push x250" \
    "make push x250" \
    "user@x250"

echo -e "\n${YELLOW}=== Makefile Error Cases ===${NC}"

# Test 11: make pull with invalid name
run_test "make pull with non-existent directory" \
    "make pull nonexistent" \
    "not found" \
    true

# Test 12: make push with empty REMOTE_HOST
run_test "make push with empty REMOTE_HOST" \
    "make push nohost" \
    "REMOTE_HOST.*empty\|not set" \
    true

# Test 13: make pull without target
run_test "make pull without target" \
    "make pull" \
    "Usage: make pull NAME" \
    true

# Test 14: make push without target
run_test "make push without target" \
    "make push" \
    "Usage: make push NAME" \
    true

echo -e "\n${YELLOW}=== Path Format Tests ===${NC}"

# Test 15: push with absolute path
run_test "sync-files.sh push with absolute path" \
    "./scripts/sync-files.sh push pathabs" \
    "code@server:/opt/data/"

# Test 16: pull with absolute path
run_test "sync-files.sh pull with absolute path" \
    "./scripts/sync-files.sh pull pathabs" \
    "code@server:/opt/data/"

# Test 17: push with home-relative path
run_test "sync-files.sh push with ~/path" \
    "./scripts/sync-files.sh push pathrel" \
    "code@server:~/projects/"

# Test 18: pull with home-relative path
run_test "sync-files.sh pull with ~/path" \
    "./scripts/sync-files.sh pull pathrel" \
    "code@server:~/projects/"

# Test 19: push with empty path after colon
run_test "sync-files.sh push with empty path (user@host:)" \
    "./scripts/sync-files.sh push pathempty" \
    "code@server:"

# Test 20: pull with empty path after colon
run_test "sync-files.sh pull with empty path (user@host:)" \
    "./scripts/sync-files.sh pull pathempty" \
    "code@server:"

echo -e "\n${YELLOW}=== Help Command ===${NC}"

# Test 21: help command
TESTS_TOTAL=$((TESTS_TOTAL + 1))
echo -n "Test $TESTS_TOTAL: help shows usage with NAME ... "
cd "$TEST_DIR"
if make help 2>&1 | grep -q 'pull.*NAME'; then
    echo -e "${GREEN}PASS${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}FAIL${NC} (help text not found)"
    make help 2>&1
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Cleanup
cleanup_test_env

# Print summary
echo -e "\n${YELLOW}=== Test Summary ===${NC}"
echo "Total tests: $TESTS_TOTAL"
echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed: ${RED}$TESTS_FAILED${NC}"

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "\n${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "\n${RED}Some tests failed!${NC}"
    exit 1
fi
