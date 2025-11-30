#!/bin/bash
# Comprehensive test suite for Makefile

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0

# Setup test environment
setup_test_env() {
    echo -e "${YELLOW}Setting up test environment...${NC}"

    # Create temp directory for tests
    export TEST_DIR=$(mktemp -d)
    export TEST_OUTPUT_DIR="$TEST_DIR/output"
    mkdir -p "$TEST_OUTPUT_DIR"

    # Create test docker config structure
    mkdir -p "$TEST_DIR/docker/config"

    # Create mock apps
    create_mock_app "testapp1" true
    create_mock_app "testapp2" false  # No .env file
    create_mock_app "postgres" true
    create_mock_app "glitchtip" true

    # Create mock scripts for postgres special commands
    mkdir -p "$TEST_DIR/docker/config/postgres"
    cat > "$TEST_DIR/docker/config/postgres/init-db.sh" <<'EOF'
#!/bin/bash
echo "MOCK_POSTGRES_INIT: $1" >> "$TEST_OUTPUT_DIR/docker-compose.log"
EOF
    chmod +x "$TEST_DIR/docker/config/postgres/init-db.sh"

    cat > "$TEST_DIR/docker/config/postgres/remove-db.sh" <<'EOF'
#!/bin/bash
echo "MOCK_POSTGRES_REMOVE: $1" >> "$TEST_OUTPUT_DIR/docker-compose.log"
EOF
    chmod +x "$TEST_DIR/docker/config/postgres/remove-db.sh"

    # Copy Makefile to test directory
    cp /Users/pawel/code/pawelwywiol/homelab/pve/x202/Makefile "$TEST_DIR/Makefile"

    # Add mock docker-compose to PATH
    export PATH="/Users/pawel/code/pawelwywiol/homelab/pve/x202/tests:$PATH"

    # Create mock docker executable that calls our mock script
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/docker" <<'EOF'
#!/bin/bash
# Mock docker command that delegates to mock-docker-compose
if [ "$1" = "compose" ]; then
    shift
    exec mock-docker-compose "$@"
else
    echo "MOCK_DOCKER_CMD: $*" >> "$TEST_OUTPUT_DIR/docker-compose.log"
fi
EOF
    chmod +x "$TEST_DIR/bin/docker"
    export PATH="$TEST_DIR/bin:$PATH"

    echo -e "${GREEN}Test environment ready at: $TEST_DIR${NC}"
}

create_mock_app() {
    local app_name=$1
    local with_env=$2

    mkdir -p "$TEST_DIR/docker/config/$app_name"

    # Create minimal compose.yml
    cat > "$TEST_DIR/docker/config/$app_name/compose.yml" <<EOF
services:
  $app_name:
    image: test/$app_name:latest
EOF

    # Create .env if requested
    if [ "$with_env" = true ]; then
        cat > "$TEST_DIR/docker/config/$app_name/.env" <<EOF
TEST_VAR=test_value
EOF
    fi
}

cleanup_test_env() {
    echo -e "${YELLOW}Cleaning up test environment...${NC}"
    rm -rf "$TEST_DIR"
}

reset_log() {
    rm -f "$TEST_OUTPUT_DIR/docker-compose.log"
    touch "$TEST_OUTPUT_DIR/docker-compose.log"
}

run_test() {
    local test_name=$1
    local test_cmd=$2
    local expected_pattern=$3
    local should_fail=${4:-false}
    local check_log=${5:-true}

    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    reset_log

    echo -n "Test $TESTS_TOTAL: $test_name ... "

    # Run command in test directory
    cd "$TEST_DIR"

    if [ "$should_fail" = true ]; then
        # Command should fail
        if $test_cmd 2>&1 | grep -q "$expected_pattern"; then
            echo -e "${GREEN}PASS${NC}"
            TESTS_PASSED=$((TESTS_PASSED + 1))
        else
            echo -e "${RED}FAIL${NC} (expected failure pattern not found)"
            echo "Output was:"
            $test_cmd 2>&1 || true
            TESTS_FAILED=$((TESTS_FAILED + 1))
        fi
    else
        # Command should succeed
        local cmd_output=$(mktemp)
        if $test_cmd &>"$cmd_output"; then
            # Check log for expected pattern if needed
            if [ "$check_log" = true ]; then
                if grep -q "$expected_pattern" "$TEST_OUTPUT_DIR/docker-compose.log" 2>/dev/null; then
                    echo -e "${GREEN}PASS${NC}"
                    TESTS_PASSED=$((TESTS_PASSED + 1))
                else
                    echo -e "${RED}FAIL${NC} (expected pattern not found in log)"
                    echo "Expected: $expected_pattern"
                    echo "Log contents:"
                    cat "$TEST_OUTPUT_DIR/docker-compose.log" 2>/dev/null || echo "(empty)"
                    TESTS_FAILED=$((TESTS_FAILED + 1))
                fi
            else
                # Just check command succeeded
                echo -e "${GREEN}PASS${NC}"
                TESTS_PASSED=$((TESTS_PASSED + 1))
            fi
        else
            echo -e "${RED}FAIL${NC} (command failed)"
            echo "Output was:"
            cat "$cmd_output"
            TESTS_FAILED=$((TESTS_FAILED + 1))
        fi
        rm -f "$cmd_output"
    fi
}

# Test suite
echo -e "${YELLOW}=== Makefile Test Suite ===${NC}\n"

setup_test_env

echo -e "\n${YELLOW}=== Generic App Commands ===${NC}"

# Test 1: Generic app with .env - up
run_test "testapp1 up (with .env)" \
    "make testapp1 up" \
    "MOCK_COMPOSE_CMD: --env-file ./docker/config/testapp1/.env -f ./docker/config/testapp1/compose.yml up -d"

# Test 2: Generic app without .env - up
run_test "testapp2 up (no .env)" \
    "make testapp2 up" \
    "MOCK_COMPOSE_CMD: -f ./docker/config/testapp2/compose.yml up -d"

# Test 3: Generic app - down
run_test "testapp1 down" \
    "make testapp1 down" \
    "MOCK_COMPOSE_CMD: -f ./docker/config/testapp1/compose.yml down"

# Test 4: Generic app - restart
run_test "testapp1 restart" \
    "make testapp1 restart" \
    "MOCK_COMPOSE_CMD: -f ./docker/config/testapp1/compose.yml restart"

# Test 5: Generic app - pull
run_test "testapp1 pull" \
    "make testapp1 pull" \
    "MOCK_COMPOSE_CMD: -f ./docker/config/testapp1/compose.yml pull"

echo -e "\n${YELLOW}=== Special Commands - Postgres ===${NC}"

# Test 6: Postgres up
run_test "postgres up" \
    "make postgres up" \
    "MOCK_COMPOSE_CMD: --env-file ./docker/config/postgres/.env -f ./docker/config/postgres/compose.yml up -d"

# Test 7: Postgres add database
run_test "postgres add testdb" \
    "make postgres add testdb" \
    "MOCK_POSTGRES_INIT: testdb"

# Test 8: Postgres remove database
run_test "postgres remove testdb" \
    "make postgres remove testdb" \
    "MOCK_POSTGRES_REMOVE: testdb"

echo -e "\n${YELLOW}=== Special Commands - GlitchTip ===${NC}"

# Test 9: GlitchTip up
run_test "glitchtip up" \
    "make glitchtip up" \
    "MOCK_COMPOSE_CMD: --env-file ./docker/config/glitchtip/.env -f ./docker/config/glitchtip/compose.yml up -d"

# Test 10: GlitchTip createsuperuser
run_test "glitchtip createsuperuser" \
    "make glitchtip createsuperuser" \
    "MOCK_COMPOSE_CMD:.*run glitchtip-migrate ./manage.py createsuperuser"

echo -e "\n${YELLOW}=== Error Cases ===${NC}"

# Test 11: Non-existent app
run_test "non-existent app error" \
    "make nonexistent up" \
    "Error: App 'nonexistent' not found" \
    true

# Test 12: Missing action
run_test "missing action error" \
    "make testapp1" \
    "Usage: make testapp1" \
    true

# Test 13: Invalid action
run_test "invalid action error" \
    "make testapp1 invalid" \
    "Invalid action 'invalid'" \
    true

# Test 14: Postgres add without db name
run_test "postgres add without db name" \
    "make postgres add" \
    "Usage: make postgres add SOME_DB_NAME" \
    true

# Test 15: Postgres remove without db name
run_test "postgres remove without db name" \
    "make postgres remove" \
    "Usage: make postgres remove SOME_DB_NAME" \
    true

echo -e "\n${YELLOW}=== Utility Commands ===${NC}"

# Test 16: Random command (doesn't use docker-compose)
run_test "random hex generation" \
    "make random" \
    "" \
    false \
    false

# Test 17: Help command (doesn't use docker-compose)
run_test "help command" \
    "make help" \
    "" \
    false \
    false

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
