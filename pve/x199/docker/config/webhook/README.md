# GitHub Webhook Handler

Lightweight webhook service for triggering Ansible deployments and OpenTofu infrastructure updates on x199 control node.

## Architecture

```
GitHub Push → webhook.wywiol.eu (Caddy) → webhook:8097 (adnanh/webhook) → {
  Semaphore API → Ansible playbooks (x202/x201 services)
  OpenTofu → Infrastructure updates (plan/apply)
  ntfy.sh → Notifications
}
```

## Security Layers

1. **GitHub IP Whitelist** (Caddy) - 140.82.112.0/20, 185.199.108.0/22, 192.30.252.0/22
2. **HMAC-SHA256 Signature** (webhook) - Verifies GitHub authenticity
3. **Repository Filter** - Only allows `PawelWywiol/homelab`
4. **Branch Filter** - Only triggers on `main` branch
5. **Path-based Routing** - Selective triggers based on changed files

## Webhook Endpoints

| Endpoint | Trigger | Action |
|----------|---------|--------|
| `/hooks/deploy-x202-services` | Changes in `pve/x202/` | Deploy x202 services via Semaphore |
| `/hooks/deploy-x201-services` | Changes in `pve/x201/` | Deploy x201 services via Semaphore |
| `/hooks/update-infrastructure` | Changes in `pve/x199/infra/tofu/` | Run OpenTofu plan (+ optional apply) |
| `/hooks/check-ansible` | Changes in `pve/x199/ansible/` | Ansible syntax check via Semaphore |
| `/hooks/health` | Anytime | Health check (no auth) |

## Setup Instructions

### 1. Prerequisites

**Already installed by bootstrap.sh:**
- ✅ Caddy reverse proxy (GitHub IP whitelist configured)
- ✅ Semaphore UI (API endpoint at localhost:3001)
- ✅ Webhook service (running on port 8097)

### 2. Configure Semaphore API Token

After Semaphore is running, generate an API token:

```bash
# Access Semaphore UI
open http://semaphore.local.wywiol.eu

# Go to: User Settings → API Tokens → Create New Token
# Copy the token
```

Update webhook configuration:

```bash
# Edit .env file
nano docker/config/webhook/.env

# Update:
SEMAPHORE_API_TOKEN=your-actual-token-here

# Restart webhook service
make webhook restart
```

### 3. Create Semaphore Projects & Templates

Create projects and templates in Semaphore UI for:

1. **x202 Services Deployment**
   - Template ID: 1
   - Playbook: `ansible/playbooks/deploy-service.yml`
   - Extra vars: `target=x202`

2. **x201 Services Deployment**
   - Template ID: 2
   - Playbook: `ansible/playbooks/deploy-service.yml`
   - Extra vars: `target=x201`

3. **Ansible Syntax Check**
   - Template ID: 3
   - Command: `ansible-playbook --syntax-check ansible/playbooks/*.yml`

Update template IDs in `.env` if different:

```bash
SEMAPHORE_TEMPLATE_X202=1
SEMAPHORE_TEMPLATE_X201=2
SEMAPHORE_TEMPLATE_ANSIBLE_CHECK=3
```

### 4. Configure GitHub Webhook

In your GitHub repository (`PawelWywiol/homelab`):

1. Go to **Settings** → **Webhooks** → **Add webhook**

2. Configure:
   - **Payload URL**: `https://webhook.wywiol.eu/hooks/deploy-x202-services`
   - **Content type**: `application/json`
   - **Secret**: (from `~/docker/config/webhook/.env` → `GITHUB_WEBHOOK_SECRET`)
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

### 5. Verify Setup

**Test health endpoint:**
```bash
curl https://webhook.wywiol.eu/hooks/health
# Expected: "Webhook service healthy"
```

**Check webhook logs:**
```bash
make webhook logs
```

**Check Semaphore for triggered tasks:**
```bash
open http://semaphore.local.wywiol.eu
# Go to: Projects → Tasks
```

**Monitor notifications:**
```bash
# Subscribe to ntfy topic (optional)
curl -s https://ntfy.sh/homelab-webhooks/json
```

## Configuration

### Environment Variables (.env)

| Variable | Description | Default |
|----------|-------------|---------|
| `GITHUB_WEBHOOK_SECRET` | GitHub webhook secret (HMAC) | Auto-generated |
| `SEMAPHORE_URL` | Semaphore API endpoint | http://localhost:3001 |
| `SEMAPHORE_API_TOKEN` | Semaphore API token | **REQUIRED** |
| `SEMAPHORE_PROJECT_ID` | Semaphore project ID | 1 |
| `TOFU_AUTO_APPLY` | Auto-apply infrastructure changes | false |
| `NTFY_ENABLED` | Enable ntfy notifications | true |
| `NTFY_TOPIC` | ntfy.sh topic name | homelab-webhooks |
| `LOG_LEVEL` | Logging verbosity | info |

### Semaphore Template Mapping

Edit `.env` to match your Semaphore template IDs:

```bash
SEMAPHORE_TEMPLATE_X202=1      # x202 deployment template
SEMAPHORE_TEMPLATE_X201=2      # x201 deployment template
SEMAPHORE_TEMPLATE_ANSIBLE_CHECK=3  # Ansible syntax check
```

### OpenTofu Auto-Apply

**⚠️ NOT RECOMMENDED** - Manual approval is safer

To enable automatic infrastructure updates:

```bash
# Edit .env
TOFU_AUTO_APPLY=true

# Restart webhook
docker compose restart
```

With auto-apply disabled (default), you'll receive notifications to manually apply:

```bash
cd ~/infra/tofu
tofu apply /tmp/tofu-plan-*.tfplan
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

### Check Semaphore API

Test Semaphore API manually:

```bash
# Get API token from .env
source docker/config/webhook/.env

# Test API connection
curl -H "Authorization: Bearer $SEMAPHORE_API_TOKEN" \
  http://localhost:3001/api/projects

# Expected: JSON list of projects
```

### Signature Verification Failed

Regenerate webhook secret:

```bash
# Generate new secret
NEW_SECRET=$(openssl rand -hex 32)

# Update .env
sed -i "s/GITHUB_WEBHOOK_SECRET=.*/GITHUB_WEBHOOK_SECRET=$NEW_SECRET/" \
  docker/config/webhook/.env

# Restart webhook
make webhook restart

# Update GitHub webhook with new secret
echo "New secret: $NEW_SECRET"
```

### OpenTofu Plan Fails

**Check OpenTofu state:**

```bash
cd ~/infra/tofu
tofu init
tofu validate
tofu plan
```

**Common issues:**
- Proxmox API token expired
- State file locked
- Missing terraform.tfvars

### Notifications Not Working

**Test ntfy.sh:**

```bash
curl -d "Test notification" https://ntfy.sh/homelab-webhooks
```

**Subscribe to notifications:**

- Web: https://ntfy.sh/homelab-webhooks
- Mobile: Install ntfy app → Subscribe to `homelab-webhooks`
- CLI: `curl -s https://ntfy.sh/homelab-webhooks/json`

## Maintenance

### Update Webhook Service

```bash
make webhook pull && make webhook up
```

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

**Semaphore API token:**

```bash
# Generate new token in Semaphore UI
# Update docker/config/webhook/.env (SEMAPHORE_API_TOKEN)
# Restart: make webhook restart
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
- `~/.semaphore/config/` (Semaphore database)
- `~/docker/config/webhook/.env` (webhook secrets)

**Manual backup:**

```bash
# Backup webhook config
tar -czf webhook-config-backup-$(date +%Y%m%d).tar.gz \
  docker/config/webhook/.env \
  docker/config/webhook/hooks.yml

# Backup control node
make backup
```

## Advanced Configuration

### Custom Hook Rules

Edit `docker/config/webhook/hooks.yml` to add custom triggers:

```yaml
- id: "custom-hook"
  execute-command: "/scripts/custom-script.sh"
  trigger-rule:
    and:
      - match:
          type: "payload-hmac-sha256"
          secret: "${GITHUB_WEBHOOK_SECRET}"
          parameter:
            source: "header"
            name: "X-Hub-Signature-256"
      # Add custom rules here
```

After editing, reload configuration:

```bash
# Webhook service has hotreload enabled
# Changes apply automatically within ~5 seconds

# Or restart manually:
docker compose restart
```

### Multiple Repositories

To support additional repositories:

1. Update hooks.yml with new repository filters
2. Generate separate webhook secret per repo (recommended)
3. Configure each GitHub repo with its own webhook

### Disable Specific Hooks

Comment out unwanted hooks in `hooks.yml`:

```yaml
# - id: "deploy-x201-services"
#   execute-command: "/scripts/trigger-semaphore.sh"
#   ...
```

Reload applies automatically.

## Security Best Practices

1. ✅ **Never commit .env files** - Contains secrets
2. ✅ **Rotate secrets quarterly** - Webhook + API tokens
3. ✅ **Monitor webhook logs** - Check for unauthorized attempts
4. ✅ **Keep auto-apply disabled** - Manual approval for infrastructure
5. ✅ **Use dedicated Semaphore API token** - Minimal permissions
6. ✅ **Backup webhook secrets** - Store in Ansible Vault + password manager
7. ✅ **Test webhook changes** - Use GitHub "Redeliver" feature

## References

- [adnanh/webhook Documentation](https://github.com/adnanh/webhook)
- [GitHub Webhook Guide](https://docs.github.com/en/webhooks)
- [Semaphore API Documentation](https://docs.semaphoreui.com/api)
- [OpenTofu Documentation](https://opentofu.org/docs/)
- [ntfy.sh Documentation](https://ntfy.sh/docs/)
