# Makefile Test Suite

Comprehensive tests for the refactored Makefile.

## Test Coverage

### Generic App Commands
- App with .env file (up/down/restart/pull)
- App without .env file (up/down/restart/pull)
- Auto-detection of docker/config apps

### Special Commands
- **postgres**: up, down, restart, pull, add DB, remove DB
- **glitchtip**: up, down, restart, pull, createsuperuser
- **utilities**: random, help

### Error Cases
- Non-existent app
- Missing action parameter
- Invalid action
- Missing required arguments for special commands

## Running Tests

```bash
# Run from tests directory
./pve/x202/tests/test-makefile.sh
```

## Test Structure

```
tests/
├── README.md              # This file
├── mock-docker-compose    # Mock docker-compose for safe testing
└── test-makefile.sh       # Main test runner
```

## How It Works

1. **Isolation**: Creates temp directory with mock docker/config structure
2. **Mocking**: Uses mock docker-compose that logs commands instead of executing
3. **Validation**: Checks command logs match expected patterns
4. **Cleanup**: Removes temp directory after tests complete

## Test Output

- **Green**: Test passed
- **Red**: Test failed
- Summary with total/passed/failed counts

## Adding New Tests

Add test case in `test-makefile.sh`:

```bash
run_test "test description" \
    "make command args" \
    "expected pattern in log" \
    false  # true if should fail
```
