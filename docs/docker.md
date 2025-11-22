# Docker Operations Guide

Reference guide for Docker and Docker Compose operations in homelab environments.

## Table of Contents

- [Configuration Management](#configuration-management)
- [Image Management](#image-management)
- [Container Management](#container-management)
- [Network Management](#network-management)
- [Volume Management](#volume-management)
- [System Cleanup](#system-cleanup)

## Configuration Management

### Validate Compose Configuration

Verify compose file syntax and configuration before deployment:

```bash
docker compose config
```

This validates the compose file and displays the merged configuration, useful for debugging variable substitution and service definitions.

### Inspect Container Environment

Verify environment variables are correctly set in running containers:

```bash
docker exec <container_name> env | grep <ENV_VARIABLE_NAME>
```

Example:
```bash
docker exec postgres env | grep POSTGRES_USER
```

## Image Management

### Update Images to Latest Versions

Pull latest images and recreate containers:

```bash
docker compose pull
docker compose up --force-recreate --build -d
docker image prune -f
```

**Explanation:**
- `pull` - Download latest images from registry
- `--force-recreate` - Recreate containers even if config unchanged
- `--build` - Rebuild images if using custom Dockerfiles
- `prune -f` - Remove dangling images without confirmation

### Remove All Images

**Warning:** This removes all images, including those in use.

```bash
docker image prune -a -f
```

Flags:
- `-a` - Remove all unused images, not just dangling
- `-f` - Force removal without confirmation

## Container Management

### Stop and Remove Containers

Remove all containers defined in compose file:

```bash
docker compose down
```

Remove all stopped containers system-wide:

```bash
docker container prune -f
```

## Network Management

### List Networks

Display all Docker networks:

```bash
docker network ls
```

### Remove Unused Networks

Remove networks not connected to any containers:

```bash
docker network prune -f
```

## Volume Management

### Remove Unused Volumes

**Warning:** This permanently deletes volume data.

```bash
docker volume prune -f
```

### Remove Dangling Volumes

Identify and remove volumes not referenced by any container:

```bash
docker volume ls
docker volume rm $(docker volume ls -qf dangling=true)
```

## System Cleanup

### Complete System Cleanup

**Warning:** Nuclear option - removes all unused Docker resources.

```bash
# Remove all stopped containers, unused networks, dangling images
docker system prune -a -f

# Remove dangling volumes
docker volume ls
docker volume rm $(docker volume ls -qf dangling=true)
```

**What gets removed:**
- All stopped containers
- All networks not used by at least one container
- All images without at least one container associated
- All build cache

**What's preserved:**
- Running containers
- Volumes (unless explicitly removed with volume commands)
- Images used by running containers

## Best Practices

1. **Always validate** compose files before deployment with `docker compose config`
2. **Use named volumes** instead of bind mounts for data persistence
3. **Regular cleanup** - Run pruning commands weekly to reclaim disk space
4. **Update strategy** - Pull images, test in dev, then update production
5. **Backup volumes** before major updates or cleanup operations

## See Also

- [Proxmox Guide](./proxmox.md) - Container and VM management
- [Linux Guide](./linux.md) - File operations and permissions
