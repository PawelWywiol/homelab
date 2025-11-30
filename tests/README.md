# Test Suite

Comprehensive tests for project Makefiles.

## Sync Makefile Tests

Tests for root-level Makefile sync commands.

### Test Coverage

**Pull Commands** (2 tests):
- Pull from valid hosts (x202, x201)
- Command format: `code@x202 -> ./pve/x202`

**Push Commands** (2 tests):
- Push to valid hosts (x202, x250)
- Command format: `./pve/x202 -> code@x202`

**Error Cases** (4 tests):
- Invalid host (not in ./pve/)
- Missing USER@HOST argument
- Proper error messages

**Help Command** (1 test):
- Displays usage information

### Running Tests

```bash
# From repo root
./tests/test-sync-makefile.sh
```

### Test Implementation

Tests use:
- Mock `sync-files.sh` script (logs commands instead of syncing)
- Isolated temp directory with mock pve structure
- No real network connections

## X202 Makefile Tests

See `pve/x202/tests/README.md` for service management Makefile tests.
