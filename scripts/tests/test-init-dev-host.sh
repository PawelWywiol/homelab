#!/bin/bash
# Test suite for init-development-host.sh
# Tests idempotency, CLI flags, and installation functions

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
SCRIPT_UNDER_TEST="$REPO_ROOT/scripts/init-development-host.sh"

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
        cp "$SCRIPT_UNDER_TEST" "$TEST_DIR/scripts/init-development-host.sh"
        chmod +x "$TEST_DIR/scripts/init-development-host.sh"
    fi

    # Create mock commands directory
    mkdir -p "$TEST_DIR/mocks"

    # Mock apt-get
    cat > "$TEST_DIR/mocks/apt-get" <<'EOF'
#!/bin/bash
echo "APT: $@" >> "$MOCK_LOG"
exit 0
EOF
    chmod +x "$TEST_DIR/mocks/apt-get"

    # Mock apt-add-repository
    cat > "$TEST_DIR/mocks/apt-add-repository" <<'EOF'
#!/bin/bash
echo "APT-ADD-REPO: $@" >> "$MOCK_LOG"
exit 0
EOF
    chmod +x "$TEST_DIR/mocks/apt-add-repository"

    # Mock curl - handles different URLs
    cat > "$TEST_DIR/mocks/curl" <<'EOF'
#!/bin/bash
echo "CURL: $@" >> "$MOCK_LOG"
# Return empty script for piped installs
echo "echo 'Mock install complete'"
exit 0
EOF
    chmod +x "$TEST_DIR/mocks/curl"

    # Mock brew
    cat > "$TEST_DIR/mocks/brew" <<'EOF'
#!/bin/bash
echo "BREW: $@" >> "$MOCK_LOG"
exit 0
EOF
    chmod +x "$TEST_DIR/mocks/brew"

    # Mock git
    cat > "$TEST_DIR/mocks/git" <<'EOF'
#!/bin/bash
echo "GIT: $@" >> "$MOCK_LOG"
exit 0
EOF
    chmod +x "$TEST_DIR/mocks/git"

    # Mock useradd
    cat > "$TEST_DIR/mocks/useradd" <<'EOF'
#!/bin/bash
echo "USERADD: $@" >> "$MOCK_LOG"
exit 0
EOF
    chmod +x "$TEST_DIR/mocks/useradd"

    # Mock usermod
    cat > "$TEST_DIR/mocks/usermod" <<'EOF'
#!/bin/bash
echo "USERMOD: $@" >> "$MOCK_LOG"
exit 0
EOF
    chmod +x "$TEST_DIR/mocks/usermod"

    # Mock chsh
    cat > "$TEST_DIR/mocks/chsh" <<'EOF'
#!/bin/bash
echo "CHSH: $@" >> "$MOCK_LOG"
exit 0
EOF
    chmod +x "$TEST_DIR/mocks/chsh"

    # Mock update-alternatives
    cat > "$TEST_DIR/mocks/update-alternatives" <<'EOF'
#!/bin/bash
echo "UPDATE-ALTERNATIVES: $@" >> "$MOCK_LOG"
exit 0
EOF
    chmod +x "$TEST_DIR/mocks/update-alternatives"

    # Mock fnm
    cat > "$TEST_DIR/mocks/fnm" <<'EOF'
#!/bin/bash
echo "FNM: $@" >> "$MOCK_LOG"
exit 0
EOF
    chmod +x "$TEST_DIR/mocks/fnm"

    # Mock infocmp - simulate kitty not installed
    cat > "$TEST_DIR/mocks/infocmp" <<'EOF'
#!/bin/bash
echo "INFOCMP: $@" >> "$MOCK_LOG"
exit 1  # Not found by default
EOF
    chmod +x "$TEST_DIR/mocks/infocmp"

    # Mock tic
    cat > "$TEST_DIR/mocks/tic" <<'EOF'
#!/bin/bash
echo "TIC: $@" >> "$MOCK_LOG"
exit 0
EOF
    chmod +x "$TEST_DIR/mocks/tic"

    # Mock systemctl
    cat > "$TEST_DIR/mocks/systemctl" <<'EOF'
#!/bin/bash
echo "SYSTEMCTL: $@" >> "$MOCK_LOG"
exit 0
EOF
    chmod +x "$TEST_DIR/mocks/systemctl"

    # Mock id - user doesn't exist by default
    cat > "$TEST_DIR/mocks/id" <<'EOF'
#!/bin/bash
echo "ID: $@" >> "$MOCK_LOG"
exit 1  # User not found
EOF
    chmod +x "$TEST_DIR/mocks/id"

    # Mock getent
    cat > "$TEST_DIR/mocks/getent" <<'EOF'
#!/bin/bash
echo "GETENT: $@" >> "$MOCK_LOG"
if [[ "$1" == "group" && "$2" == "docker" ]]; then
    echo "docker:x:999:"
    exit 0
fi
if [[ "$1" == "passwd" ]]; then
    echo "$2:x:1000:1000::/home/$2:/bin/bash"
    exit 0
fi
exit 1
EOF
    chmod +x "$TEST_DIR/mocks/getent"

    # Mock which
    cat > "$TEST_DIR/mocks/which" <<'EOF'
#!/bin/bash
echo "WHICH: $@" >> "$MOCK_LOG"
echo "/usr/bin/$1"
exit 0
EOF
    chmod +x "$TEST_DIR/mocks/which"

    # Mock command - for checking if commands exist
    # This is tricky since 'command' is a shell builtin

    # Create fake /etc/os-release
    mkdir -p "$TEST_DIR/etc"
    cat > "$TEST_DIR/etc/os-release" <<'EOF'
ID=ubuntu
VERSION_ID="22.04"
EOF

    echo -e "${GREEN}Test environment ready at: $TEST_DIR${NC}"
}

cleanup_test_env() {
    echo -e "${YELLOW}Cleaning up test environment...${NC}"
    rm -rf "$TEST_DIR"
}

reset_log() {
    rm -f "$MOCK_LOG"
    touch "$MOCK_LOG"
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
            cat "$cmd_output"
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
                cat "$cmd_output"
                TESTS_FAILED=$((TESTS_FAILED + 1))
            fi
        else
            echo -e "${RED}FAIL${NC} (command failed)"
            echo "Output:"
            cat "$cmd_output"
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
                cat "$cmd_output"
                TESTS_FAILED=$((TESTS_FAILED + 1))
            fi
        else
            echo -e "${RED}FAIL${NC} (command failed)"
            echo "Output:"
            cat "$cmd_output"
            TESTS_FAILED=$((TESTS_FAILED + 1))
        fi
    fi
    rm -f "$cmd_output"
}

# =============================================================================
# Test suite
# =============================================================================

echo -e "${YELLOW}=== init-development-host.sh Test Suite ===${NC}\n"

# Check if script exists
if [[ ! -f "$SCRIPT_UNDER_TEST" ]]; then
    echo -e "${RED}ERROR: Script not found at $SCRIPT_UNDER_TEST${NC}"
    echo "Please create the script first."
    exit 1
fi

setup_test_env

# Override PATH to use mocks
export PATH="$TEST_DIR/mocks:$PATH"

# =============================================================================
echo -e "\n${YELLOW}=== CLI Flag Tests ===${NC}"
# =============================================================================

# Test: --help flag
run_test "--help shows usage" \
    "./scripts/init-development-host.sh --help" \
    "Usage:" \
    false true

# Test: --help shows --install-php option
run_test "--help shows --install-php option" \
    "./scripts/init-development-host.sh --help" \
    "--install-php" \
    false true

# Test: --help shows --skip-node option
run_test "--help shows --skip-node option" \
    "./scripts/init-development-host.sh --help" \
    "--skip-node" \
    false true

# Test: unknown flag
run_test "unknown flag shows error" \
    "./scripts/init-development-host.sh --unknown-flag" \
    "Unknown option" \
    true

# =============================================================================
echo -e "\n${YELLOW}=== Configuration Tests ===${NC}"
# =============================================================================

# Test: loads .env file
cat > "$TEST_DIR/scripts/.env" <<'EOF'
USERNAME="testuser"
SKIP_NODE=true
EOF

run_test "loads config from .env" \
    "./scripts/init-development-host.sh --help" \
    "testuser|\.env" \
    false true

rm -f "$TEST_DIR/scripts/.env"

# =============================================================================
echo -e "\n${YELLOW}=== Default Settings Tests ===${NC}"
# =============================================================================

# Test: PHP skipped by default (SKIP_PHP=true)
run_test "PHP skipped by default (SKIP_PHP=true)" \
    "./scripts/init-development-host.sh --help" \
    "SKIP_PHP=true" \
    false true

# Test: Node installed by default (SKIP_NODE=false)
run_test "Node installed by default (SKIP_NODE=false)" \
    "./scripts/init-development-host.sh --help" \
    "SKIP_NODE=false" \
    false true

# =============================================================================
echo -e "\n${YELLOW}=== Script Structure Tests ===${NC}"
# =============================================================================

# Test: script contains homebrew install function
run_test "script has install_homebrew function" \
    "grep -q 'install_homebrew()' ./scripts/init-development-host.sh && echo found" \
    "found" \
    false true

# Test: script contains brew packages function
run_test "script has install_brew_packages function" \
    "grep -q 'install_brew_packages()' ./scripts/init-development-host.sh && echo found" \
    "found" \
    false true

# Test: script contains zsh stack function
run_test "script has install_zsh_stack function" \
    "grep -q 'install_zsh_stack()' ./scripts/init-development-host.sh && echo found" \
    "found" \
    false true

# Test: script contains php stack function
run_test "script has install_php_stack function" \
    "grep -q 'install_php_stack()' ./scripts/init-development-host.sh && echo found" \
    "found" \
    false true

# Test: script contains node stack function
run_test "script has install_node_stack function" \
    "grep -q 'install_node_stack()' ./scripts/init-development-host.sh && echo found" \
    "found" \
    false true

# Test: script installs openfortivpn
run_test "script installs openfortivpn" \
    "grep -q 'openfortivpn' ./scripts/init-development-host.sh && echo found" \
    "found" \
    false true

# Test: script installs neovim via brew
run_test "script installs neovim via brew" \
    "grep -q 'neovim' ./scripts/init-development-host.sh && echo found" \
    "found" \
    false true

# Test: script installs lazygit via brew
run_test "script installs lazygit via brew" \
    "grep -q 'lazygit' ./scripts/init-development-host.sh && echo found" \
    "found" \
    false true

# Test: script installs fnm for node version management
run_test "script installs fnm" \
    "grep -q 'fnm' ./scripts/init-development-host.sh && echo found" \
    "found" \
    false true

# Test: script has install_lazyvim function
run_test "script has install_lazyvim function" \
    "grep -q 'install_lazyvim()' ./scripts/init-development-host.sh && echo found" \
    "found" \
    false true

# Test: script clones LazyVim starter
run_test "script clones LazyVim starter" \
    "grep -q 'LazyVim/starter' ./scripts/init-development-host.sh && echo found" \
    "found" \
    false true

# Test: script installs powerlevel10k
run_test "script installs powerlevel10k" \
    "grep -q 'powerlevel10k' ./scripts/init-development-host.sh && echo found" \
    "found" \
    false true

# Test: script installs oh-my-zsh
run_test "script installs oh-my-zsh" \
    "grep -q 'ohmyzsh\|oh-my-zsh' ./scripts/init-development-host.sh && echo found" \
    "found" \
    false true

# Test: script has run_as_user_with_brew helper for PATH issues
run_test "script has run_as_user_with_brew helper" \
    "grep -q 'run_as_user_with_brew()' ./scripts/init-development-host.sh && echo found" \
    "found" \
    false true

# Test: script uses .zprofile for zsh compatibility
run_test "script uses .zprofile for brew PATH" \
    "grep -q '.zprofile' ./scripts/init-development-host.sh && echo found" \
    "found" \
    false true

# Test: script has install_docker function
run_test "script has install_docker function" \
    "grep -q 'install_docker()' ./scripts/init-development-host.sh && echo found" \
    "found" \
    false true

# Test: script installs docker-ce
run_test "script installs docker-ce" \
    "grep -q 'docker-ce' ./scripts/init-development-host.sh && echo found" \
    "found" \
    false true

# Test: script installs docker-compose-plugin
run_test "script installs docker-compose-plugin" \
    "grep -q 'docker-compose-plugin' ./scripts/init-development-host.sh && echo found" \
    "found" \
    false true

# Test: --help shows --skip-docker option
run_test "--help shows --skip-docker option" \
    "./scripts/init-development-host.sh --help" \
    "--skip-docker" \
    false true

# Test: Docker installed by default (SKIP_DOCKER=false)
run_test "Docker installed by default (SKIP_DOCKER=false)" \
    "./scripts/init-development-host.sh --help" \
    "SKIP_DOCKER=false" \
    false true

# Test: script installs PHP 7.4 and 8.3
run_test "script installs PHP 7.4" \
    "grep -q 'php7.4' ./scripts/init-development-host.sh && echo found" \
    "found" \
    false true

run_test "script installs PHP 8.3" \
    "grep -q 'php8.3' ./scripts/init-development-host.sh && echo found" \
    "found" \
    false true

# Test: script installs composer
run_test "script installs composer" \
    "grep -q 'composer' ./scripts/init-development-host.sh && echo found" \
    "found" \
    false true

# Test: script has idempotency checks (already installed patterns)
run_test "script has idempotency checks" \
    "grep -c 'already installed' ./scripts/init-development-host.sh | grep -E '^[5-9]|^[0-9]{2}' && echo found" \
    "found" \
    false true

# Test: script installs font-anonymous-pro
run_test "script installs font-anonymous-pro" \
    "grep -q 'font-anonymous-pro' ./scripts/init-development-host.sh && echo found" \
    "found" \
    false true

# Cleanup
cleanup_test_env

# =============================================================================
# Print summary
# =============================================================================

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
