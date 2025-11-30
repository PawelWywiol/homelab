#!/bin/bash
# Test suite for root Makefile sync commands

set -e

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

    # Create mock pve structure
    mkdir -p "$TEST_DIR/pve/x202"
    mkdir -p "$TEST_DIR/pve/x201"
    mkdir -p "$TEST_DIR/pve/x250"

    # Create mock sync-files.sh script
    mkdir -p "$TEST_DIR/scripts"
    cat > "$TEST_DIR/scripts/sync-files.sh" <<'EOF'
#!/bin/bash
echo "SYNC: $1 -> $2" >> "$TEST_OUTPUT_DIR/sync.log"
exit 0
EOF
    chmod +x "$TEST_DIR/scripts/sync-files.sh"

    # Copy Makefile to test directory
    if [ -f "/Users/pawel/code/pawelwywiol/homelab/Makefile" ]; then
        cp /Users/pawel/code/pawelwywiol/homelab/Makefile "$TEST_DIR/Makefile"
    else
        echo -e "${RED}ERROR: Makefile not found at /Users/pawel/code/pawelwywiol/homelab/Makefile${NC}"
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
echo -e "${YELLOW}=== Sync Makefile Test Suite ===${NC}\n"

setup_test_env

echo -e "\n${YELLOW}=== Pull Commands ===${NC}"

# Test 1: pull with valid host
run_test "pull from valid host x202" \
    "make pull code@x202" \
    "SYNC: code@x202 -> ./pve/x202"

# Test 2: pull with another valid host
run_test "pull from valid host x201" \
    "make pull user@x201" \
    "SYNC: user@x201 -> ./pve/x201"

echo -e "\n${YELLOW}=== Push Commands ===${NC}"

# Test 3: push to valid host
run_test "push to valid host x202" \
    "make push code@x202" \
    "SYNC: ./pve/x202 -> code@x202"

# Test 4: push to another valid host
run_test "push to valid host x250" \
    "make push admin@x250" \
    "SYNC: ./pve/x250 -> admin@x250"

echo -e "\n${YELLOW}=== Error Cases ===${NC}"

# Test 5: pull with invalid host
run_test "pull from non-existent host" \
    "make pull code@invalid" \
    "Error: Host 'invalid' not found in ./pve/" \
    true

# Test 6: push with invalid host
run_test "push to non-existent host" \
    "make push code@invalid" \
    "Error: Host 'invalid' not found in ./pve/" \
    true

# Test 7: pull without target
run_test "pull without target" \
    "make pull" \
    "Usage: make pull USER@HOST" \
    true

# Test 8: push without target
run_test "push without target" \
    "make push" \
    "Usage: make push USER@HOST" \
    true

echo -e "\n${YELLOW}=== Help Command ===${NC}"

# Test 9: help command (special handling)
TESTS_TOTAL=$((TESTS_TOTAL + 1))
echo -n "Test $TESTS_TOTAL: help shows usage ... "
cd "$TEST_DIR"
if make help 2>&1 | grep -q 'pull.*USER@HOST'; then
    echo -e "${GREEN}PASS${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}FAIL${NC} (help text not found)"
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
