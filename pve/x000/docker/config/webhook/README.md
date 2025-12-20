# GitHub Webhook Handler

Lightweight webhook service for triggering Ansible deployments and OpenTofu infrastructure updates on x000 control node.

## Architecture

```
GitHub Push → webhook.wywiol.eu (Caddy) → webhook:8097 (adnanh/webhook) → {
  SSH to localhost → ~/scripts/deploy.sh → Ansible playbooks
  SSH to localhost → ~/scripts/apply-tofu.sh → OpenTofu plan/apply
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
| `/hooks/deploy-x202-services` | Changes in `pve/x202/docker/config/*` | Deploy x202 services via SSH → Ansible |
| `/hooks/deploy-x201-services` | Changes in `pve/x201/*` | Deploy x201 services via SSH → Ansible |
| `/hooks/update-infrastructure` | Changes in `pve/*/vms.tf` or `pve/x000/infra/tofu/*` | Run OpenTofu plan (+ optional apply) |
| `/hooks/health` | Anytime | Health check (no auth) |

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
```bash
# Subscribe to ntfy topic
curl -s https://ntfy.sh/homelab-webhooks/json
```

## Configuration

### Environment Variables (.env)

| Variable | Description | Default |
|----------|-------------|---------|
| `GITHUB_WEBHOOK_SECRET` | GitHub webhook secret (HMAC) | Auto-generated |
| `SSH_HOST` | SSH target host | host.docker.internal |
| `SSH_USER` | SSH user | code |
| `TOFU_AUTO_APPLY` | Auto-apply infrastructure changes | false |
| `NTFY_ENABLED` | Enable ntfy notifications | true |
| `NTFY_TOPIC` | ntfy.sh topic name | homelab-webhooks |
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
cd ~/infra/tofu
tofu apply /tmp/tofu-plan-*.tfplan
```

## Host Scripts

Webhook container SSHs to localhost to execute host scripts:

### ~/scripts/deploy.sh

Triggers Ansible deployment:
```bash
deploy.sh <target> [service]
# Examples:
deploy.sh x202           # Deploy all x202 services
deploy.sh x202 caddy     # Deploy specific service
```

### ~/scripts/apply-tofu.sh

Triggers OpenTofu plan/apply:
```bash
apply-tofu.sh
# Creates plan in /tmp/tofu-plan-*.tfplan
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
#   execute-command: "/scripts/trigger-deploy.sh"
#   ...
```

Reload applies automatically.

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
- [ntfy.sh Documentation](https://ntfy.sh/docs/)
