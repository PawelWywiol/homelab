# GitHub Webhook Handler

Lightweight webhook service for triggering Ansible deployments and OpenTofu infrastructure updates on x000 control node.

## Architecture

```
GitHub Push → webhook.wywiol.eu/hooks/homelab (Caddy) → webhook:9000 (custom image with bash/jq)
                                                               ↓
                                              trigger-homelab.sh (file routing)
                                                               ↓
                    ┌────────────────────────┬────────────────────────┬────────────────────┐
                    ↓                        ↓                        ↓                    ↓
    pve/x000/docker/config/*   pve/x202/docker/config/*   pve/x000/infra/tofu/*   Folder removed
                    ↓                        ↓                        ↓                    ↓
        scripts/deploy.sh          scripts/deploy.sh        scripts/apply-tofu.sh   scripts/stop-service.sh
                    ↓                        ↓                        ↓                    ↓
            Deploy to x000            Deploy to x202            OpenTofu plan        Stop containers
                    ↓                        ↓                        ↓                    ↓
        📦 Start + ✅/❌ End    📦 Start + ✅/❌ End    🔧 Start + ✅/❌ End   🛑 Start + ✅/❌ End
              Discord                  Discord                  Discord                Discord
```

## Security Layers

1. **GitHub IP Whitelist** (Caddy) - 140.82.112.0/20, 185.199.108.0/22, 192.30.252.0/22
2. **HMAC-SHA256 Signature** (webhook) - Verifies GitHub authenticity
3. **Repository Filter** - Only allows `PawelWywiol/homelab`
4. **Branch Filter** - Only triggers on `main` branch
5. **File-based Routing** - Routes actions based on changed files

## Custom Docker Image

The webhook service uses a custom Docker image built from `almir/webhook:2.8.2` with additional dependencies:

**Dockerfile additions:**
- `bash` - Required for scripts using bash-specific syntax (arrays, `${BASH_SOURCE}`)
- `jq` - JSON parsing for webhook payload processing
- `openssh-client` - SSH to host for executing deployment scripts

**compose.yml flags:**
- `-template` - Enables Go template syntax in hooks.yml for environment variable expansion

**hooks.yml syntax:**
```yaml
# Environment variables use Go template syntax (NOT shell ${VAR} syntax)
secret: '{{ getenv "GITHUB_WEBHOOK_SECRET" }}'
```

## Webhook Endpoints

| Endpoint | Action |
|----------|--------|
| `/hooks/homelab` | Unified handler - routes by changed files |
| `/hooks/health` | Health check (no auth) |

**File routing:**
| Changed Files | Action |
|--------------|--------|
| `pve/x000/docker/config/*` | Deploy x000 services via Ansible |
| `pve/x202/docker/config/*` | Deploy x202 services via Ansible |
| `pve/x000/infra/tofu/*` | Run OpenTofu plan |
| Folder removed from `pve/x*/docker/config/*` | Stop & remove containers |

**Two-phase notifications:**
Each action sends two Discord notifications:
1. **Start** - When trigger fires (📦 deploy, 🔧 tofu, 🛑 stop)
2. **End** - After execution (✅ success / ❌ failure + duration)

## Setup Instructions

### 1. Prerequisites

**Installed by setup.sh:**
- Caddy reverse proxy (GitHub IP whitelist configured)
- Webhook service (running on port 8097)
- SSH keys for localhost access

### 2. Configure GitHub Webhook

In your GitHub repository (`PawelWywiol/homelab`):

1. Go to **Settings** → **Webhooks** → **Add webhook**

2. Configure:
   - **Payload URL**: `https://webhook.wywiol.eu/hooks/homelab`
   - **Content type**: `application/json`
   - **Secret**: (from `docker/config/webhook/.env` → `GITHUB_WEBHOOK_SECRET`)
   - **SSL verification**: Enable
   - **Events**: Just the push event
   - **Active**: ✓

3. Click **Add webhook**

4. Test by pushing to main branch:
   ```bash
   git commit --allow-empty -m "test: webhook trigger"
   git push origin main
   ```

5. Check webhook deliveries in GitHub UI for successful response

### 3. Verify Setup

**Test health endpoint:**
```bash
curl https://webhook.wywiol.eu/hooks/health
# Expected: "Webhook service healthy"
```

**Check webhook logs:**
```bash
make webhook logs
```

**Monitor notifications:**
Notifications are sent to configured Discord channel via webhook.

## Configuration

### Environment Variables (.env)

| Variable | Description | Default |
|----------|-------------|---------|
| `GITHUB_WEBHOOK_SECRET` | GitHub webhook secret (HMAC) | Auto-generated |
| `SSH_HOST` | SSH target host | host.docker.internal |
| `SSH_USER` | SSH user | code |
| `TOFU_AUTO_APPLY` | Auto-apply infrastructure changes | false |
| `DISCORD_ENABLED` | Enable Discord notifications | true |
| `DISCORD_WEBHOOK_URL` | Discord webhook URL | - |
| `LOG_LEVEL` | Logging verbosity | info |

### OpenTofu Auto-Apply

**NOT RECOMMENDED** - Manual approval is safer

To enable automatic infrastructure updates:

```bash
# Edit .env
TOFU_AUTO_APPLY=true

# Restart webhook
docker compose restart
```

With auto-apply disabled (default), you'll receive notifications to manually apply:

```bash
cd infra/tofu
tofu apply
```

## Host Scripts

Webhook container SSHs to localhost to execute scripts in `~/homelab/pve/x000/scripts/`:

### scripts/deploy.sh

Triggers Ansible deployment:
```bash
deploy.sh <target> [service]
# Examples:
deploy.sh x000           # Deploy all x000 services
deploy.sh x202           # Deploy all x202 services
deploy.sh x202 caddy     # Deploy specific service
```

### scripts/stop-service.sh

Stops and removes containers when folder is removed:
```bash
stop-service.sh <target> <service>
# Examples:
stop-service.sh x000 caddy   # Stop caddy on x000
stop-service.sh x202 n8n     # Stop n8n on x202
```

### scripts/apply-tofu.sh

Triggers OpenTofu plan/apply:
```bash
apply-tofu.sh
# Creates plan and notifies
# Auto-applies if TOFU_AUTO_APPLY=true
```

## Troubleshooting

### Webhook Not Triggering

**Check GitHub delivery:**
1. Go to GitHub repo → Settings → Webhooks
2. Click on webhook → Recent Deliveries
3. Check response status and body

**Common issues:**
- **403 Forbidden**: IP not whitelisted (check Caddy config)
- **401 Unauthorized**: Signature mismatch (check GITHUB_WEBHOOK_SECRET)
- **404 Not Found**: Incorrect endpoint URL
- **500 Server Error**: Check webhook logs

### Check Webhook Logs

```bash
make webhook logs
```

### SSH Connection Fails

Test SSH from webhook container:
```bash
docker exec -it webhook ssh -o StrictHostKeyChecking=no code@host.docker.internal "echo OK"
```

**Common issues:**
- SSH key not mounted in container
- SSH key permissions wrong (should be 600)
- Host user doesn't accept key

### Signature Verification Failed

**Common causes:**
- Secret mismatch between GitHub and `.env` file
- Missing `-template` flag in compose.yml (env vars not expanded)
- Wrong syntax in hooks.yml (must use `{{ getenv "VAR" }}` not `${VAR}`)

**Verify secret is loaded:**
```bash
docker exec webhook sh -c 'echo $GITHUB_WEBHOOK_SECRET'
```

**Regenerate webhook secret:**
```bash
# Generate new secret
NEW_SECRET=$(openssl rand -hex 32)

# Update .env
sed -i "s/GITHUB_WEBHOOK_SECRET=.*/GITHUB_WEBHOOK_SECRET=$NEW_SECRET/" \
  docker/config/webhook/.env

# Restart webhook (down+up to reload .env)
make webhook down && make webhook up

# Update GitHub webhook with new secret
echo "New secret: $NEW_SECRET"
```

**Note:** `make webhook restart` properly reloads .env files (uses down+up internally).

### OpenTofu Plan Fails

**Check OpenTofu state:**

```bash
cd infra/tofu
tofu init
tofu validate
tofu plan
```

**Common issues:**
- Proxmox API token expired
- State file locked
- Missing terraform.tfvars

### Notifications Not Working

**Test Discord webhook:**

```bash
curl -H "Content-Type: application/json" \
  -d '{"content": "Test notification"}' \
  "$DISCORD_WEBHOOK_URL"
```

**Check webhook URL:**
- Ensure `DISCORD_WEBHOOK_URL` is set in `.env`
- Verify webhook exists in Discord (Server Settings → Integrations → Webhooks)
- Check webhook logs: `make webhook logs`

## Maintenance

### Update Webhook Service

```bash
# Rebuild custom image and restart
docker compose -f ./docker/config/webhook/compose.yml build
make webhook down && make webhook up
```

**Note:** Uses custom Dockerfile, so `make webhook pull` won't update the base image. Rebuild to pick up Dockerfile changes or base image updates.

### Rotate Secrets

**GitHub webhook secret:**

```bash
# Generate new secret
openssl rand -hex 32

# Update in:
# 1. docker/config/webhook/.env (GITHUB_WEBHOOK_SECRET)
# 2. GitHub repo webhook settings (Secret field)
# 3. Restart: make webhook restart
```

### View Webhook Statistics

```bash
# Container stats
docker stats webhook

# Service logs (last 100 lines)
docker compose logs --tail=100 webhook

# Follow live logs
docker compose logs -f webhook
```

### Backup Configuration

**Automated** (included in `backup-control-node.sh`):
- `docker/config/webhook/.env` (webhook secrets)

**Manual backup:**

```bash
# Backup webhook config
tar -czf webhook-config-backup-$(date +%Y%m%d).tar.gz \
  docker/config/webhook/.env \
  docker/config/webhook/hooks.yml \
  docker/config/webhook/Dockerfile

# Backup control node
make backup
```

## Adding New Hosts

To add automation for new hosts (e.g., x203):

1. Edit `trigger-homelab.sh`:
   - Add new arrays:
     ```bash
     SERVICES_TO_START_X203=()
     SERVICES_TO_RESTART_X203=()
     SERVICES_TO_STOP_X203=()
     ```
   - Add extract helper:
     ```bash
     extract_service_x203() {
         echo "$1" | sed -n 's|pve/x203/docker/config/\([^/]*\)/.*|\1|p'
     }
     ```
   - Add file pattern matching in each loop (added/modified/removed)
   - Add DEPLOY_X203/STOP_X203 flags
   - Add execution blocks for deploy and stop

2. Edit `common.sh`:
   - Add notification types: `deploy_x203`, `stop_x203`

3. Add Ansible inventory entry for new host

4. Push changes to main branch

## Security Best Practices

1. **Never commit .env files** - Contains secrets
2. **Rotate secrets quarterly** - Webhook secret
3. **Monitor webhook logs** - Check for unauthorized attempts
4. **Keep auto-apply disabled** - Manual approval for infrastructure
5. **Backup webhook secrets** - Store in Ansible Vault + password manager
6. **Test webhook changes** - Use GitHub "Redeliver" feature

## References

- [adnanh/webhook Documentation](https://github.com/adnanh/webhook)
- [GitHub Webhook Guide](https://docs.github.com/en/webhooks)
- [OpenTofu Documentation](https://opentofu.org/docs/)
- [Discord Webhooks Guide](https://discord.com/developers/docs/resources/webhook)
