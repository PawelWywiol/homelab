# Documentation

Professional reference documentation for homelab infrastructure management.

## Table of Contents

### Core Infrastructure

- **[Docker](./docker.md)** - Docker and Docker Compose operations
  - Configuration management
  - Image and container lifecycle
  - Volume and network management
  - System cleanup and maintenance

- **[Proxmox](./proxmox.md)** - Proxmox VE administration
  - Storage management
  - VM and LXC operations
  - Filesystem maintenance
  - Cloud-init templates

- **[Linux](./linux.md)** - Linux system administration
  - File operations and synchronization
  - Permissions management
  - SSH configuration
  - Disk management and LVM

### Development Environments

- **[WSL](./wsl.md)** - Windows Subsystem for Linux setup
  - WSL2 installation and configuration
  - Docker integration
  - SSH access and networking
  - Troubleshooting and automation

## Quick Reference

### Common Tasks

| Task | Guide | Section |
|------|-------|---------|
| Update Docker containers | [Docker](./docker.md#update-images-to-latest-versions) | Image Management |
| Add disk to Proxmox | [Proxmox](./proxmox.md#prepare-external-disk-drive) | Storage Management |
| Sync files with rsync | [Linux](./linux.md#file-synchronization) | File Operations |
| Fix LXC container | [Proxmox](./proxmox.md#container-filesystem-check) | LXC Operations |
| Setup WSL SSH | [WSL](./wsl.md#ssh-configuration) | SSH Configuration |
| Resize LVM partition | [Linux](./linux.md#resize-lvm-partition) | Disk Management |
| Create VM template | [Proxmox](./proxmox.md#create-debian-cloud-init-template) | Cloud-Init Templates |
| Docker cleanup | [Docker](./docker.md#system-cleanup) | System Cleanup |

### Emergency Procedures

| Emergency | Guide | Section |
|-----------|-------|---------|
| Corrupted filesystem | [Proxmox](./proxmox.md#fix-corrupted-filesystem) | Filesystem Maintenance |
| Container won't start | [Proxmox](./proxmox.md#container-wont-start) | Troubleshooting |
| Storage full | [Proxmox](./proxmox.md#storage-full) | Troubleshooting |
| Docker cleanup | [Docker](./docker.md#complete-system-cleanup) | System Cleanup |

## Document Structure

Each guide follows a consistent structure for easy navigation:

1. **Table of Contents** - Quick navigation to sections
2. **Organized Sections** - Grouped by functionality
3. **Command Examples** - Real-world usage examples
4. **Best Practices** - Recommended approaches
5. **Troubleshooting** - Common issues and solutions
6. **See Also** - Related documentation links

## Contributing

When adding new documentation:

1. **Follow existing format** - Use established section structure
2. **Include examples** - Provide working command examples
3. **Explain flags** - Document command options and parameters
4. **Add context** - Explain when and why to use commands
5. **Cross-reference** - Link to related documentation
6. **Update index** - Add entries to this README

## See Also

- [Root README](../README.md) - Repository overview
- [CLAUDE.md](../CLAUDE.md) - Complete setup guide and commands
- [Scripts](../scripts/README.md) - Automation utilities
