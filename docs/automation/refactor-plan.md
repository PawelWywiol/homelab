# Automation Workflow Refactor Plan

**Status**: Completed
**Created**: 2025-12-19
**Completed**: 2025-12-21
**Author**: Claude Code

## Overview

Refactor homelab automation from Webhook → Semaphore → Ansible to simplified Webhook → SSH → Ansible architecture. Remove Semaphore, enable distributed `vms.tf` per pve folder.

### Key Changes

| Before | After |
|--------|-------|
| Webhook → Semaphore API → Ansible | Webhook → SSH to localhost → Ansible |
| Semaphore for all Ansible runs | Direct ansible-playbook |
| `bootstrap.sh` | `setup.sh` |
| No bulk service management | `make all up/down` on x000 |
| Centralized vms.tf | Distributed vms.tf per pve folder |

## Architecture

### Current Flow
```
GitHub Push → webhook:8097 → Semaphore API → Ansible Playbook
                   ↓
            HMAC verification
```

### New Flow
```
GitHub Push → webhook:8097 → SSH code@localhost → ~/scripts/deploy.sh
                   ↓                                       ↓
            HMAC verification                    git pull + ansible-playbook
                                                           ↓
                                                 SSH to target VM
                                                           ↓
                                                 docker compose pull/up
```

## Implementation Phases

### Phase 0: Documentation (This File)
Create implementation plan documentation.

### Phase 1: Rename bootstrap.sh → setup.sh

**Files:**
- `pve/x000/bootstrap.sh` → `pve/x000/setup.sh`
- `pve/x000/bootstrap.env.example` → `pve/x000/setup.env.example`
- `pve/x000/Makefile` - Update target name

**Changes:**
1. Rename files
2. Update Makefile `bootstrap` → `setup` target
3. Update help text and internal comments

### Phase 2: Add `make all` Target (x000 only)

**File:** `pve/x000/Makefile`

**New target:**
```makefile
.PHONY: all
all:
    @ACTION="$(word 2, $(MAKECMDGOALS))"; \
    case "$$ACTION" in \
        up) \
            $(MAKE) caddy up && \
            $(MAKE) webhook up && \
            $(MAKE) portainer up ;; \
        down) \
            $(MAKE) portainer down; \
            $(MAKE) webhook down; \
            $(MAKE) caddy down ;; \
        *) echo "Usage: make all [up|down]" ;; \
    esac
```

**Note:** Semaphore removed from startup sequence.

### Phase 3: Webhook Refactor

**Approach:** SSH to localhost (code@host.docker.internal)

**Files to create:**
- `pve/x000/scripts/deploy.sh` - Host deployment script
- `pve/x000/scripts/apply-tofu.sh` - Host OpenTofu script

**Files to remove:**
- `pve/x000/docker/config/semaphore/` - Entire directory
- `pve/x000/docker/config/webhook/scripts/trigger-semaphore.sh`

**Files to modify:**
- `pve/x000/docker/config/webhook/hooks.yml` - Update triggers
- `pve/x000/docker/config/webhook/scripts/trigger-deploy.sh` - SSH approach
- `pve/x000/docker/config/webhook/scripts/trigger-tofu.sh` - SSH approach
- `pve/x000/docker/config/webhook/compose.yml` - Mount SSH keys
- `pve/x000/docker/config/webhook/.env.example` - Remove Semaphore vars

**Hook triggers:**
| Path Pattern | Action |
|--------------|--------|
| `pve/x202/docker/config/*` | `trigger-deploy.sh x202` |
| `pve/x201/*` | `trigger-deploy.sh x201` |
| `pve/*/vms.tf` | `trigger-tofu.sh` |

### Phase 4: Simplify Ansible Playbook

**File:** `pve/x000/ansible/playbooks/deploy-service.yml`

Simplified to:
1. SSH to target host
2. cd to service directory
3. `docker compose pull`
4. `docker compose up -d --remove-orphans`

Remove git pull from playbook (handled by host script).

### Phase 5: OpenTofu Distributed vms.tf

**Current:** All VMs in `pve/x000/infra/tofu/vms.tf`
**Target:** Individual `vms.tf` in each pve folder

- Provider config stays in `pve/x000/infra/tofu/provider.tf`
- Webhook watches `pve/*/vms.tf` pattern
- x000 executes all tofu operations

**Recommended:** Keep centralized for now, document distributed pattern.

### Phase 6: Documentation Update

**Files:**
- `docs/automation/ansible-opentofu-automation.md` - Complete rewrite
- `CLAUDE.md` - Update quick start
- `pve/x000/README.md` - Update setup instructions

## Files Summary

### Create
| File | Purpose |
|------|---------|
| `docs/automation/refactor-plan.md` | This implementation plan |
| `pve/x000/scripts/deploy.sh` | Host deployment script |
| `pve/x000/scripts/apply-tofu.sh` | Host OpenTofu script |
| `pve/x000/ansible/playbooks/_deploy_single.yml` | Helper task |

### Rename
| From | To |
|------|-----|
| `pve/x000/bootstrap.sh` | `pve/x000/setup.sh` |
| `pve/x000/bootstrap.env.example` | `pve/x000/setup.env.example` |

### Remove
| File | Reason |
|------|--------|
| `pve/x000/docker/config/semaphore/` | No longer needed |
| `pve/x000/docker/config/webhook/scripts/trigger-semaphore.sh` | Replaced by SSH |

### Modify
| File | Changes |
|------|---------|
| `pve/x000/Makefile` | Add `setup`, `all` targets |
| `pve/x000/docker/config/webhook/hooks.yml` | Update triggers |
| `pve/x000/docker/config/webhook/scripts/trigger-deploy.sh` | SSH approach |
| `pve/x000/docker/config/webhook/scripts/trigger-tofu.sh` | SSH approach |
| `pve/x000/docker/config/webhook/compose.yml` | Mount SSH keys |
| `pve/x000/docker/config/webhook/.env.example` | Remove Semaphore vars |
| `pve/x000/ansible/playbooks/deploy-service.yml` | Simplify |
| `docs/automation/ansible-opentofu-automation.md` | Full update |
| `CLAUDE.md` | Update quick start |

## Testing Plan

1. **Phase 1:** Verify `make setup` works
2. **Phase 2:** Test `make all up` / `make all down` on x000
3. **Phase 3:** Manual webhook test, verify SSH to localhost
4. **Phase 4:** `ansible-playbook ... --check`
5. **End-to-end:** Push to `pve/x202/docker/config/*`, verify deployment

## Security Considerations

- Repository will be public
- No secrets in committed files (.env files gitignored)
- SSH keys mounted read-only in webhook container
- HMAC verification for webhook authenticity
- GitHub IP whitelist in Caddy

## Rollback Plan

If issues arise:
1. Restore `bootstrap.sh` from git
2. Restore Semaphore directory from backup
3. Restore original `trigger-semaphore.sh`
4. Update Makefile to use `bootstrap` target

---

**Last Updated:** 2025-12-21
