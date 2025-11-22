# Proxmox VE Administration Guide

Comprehensive guide for Proxmox Virtual Environment operations, storage management, and virtualization tasks.

## Table of Contents

- [Storage Management](#storage-management)
- [VM Operations](#vm-operations)
- [LXC Container Operations](#lxc-container-operations)
- [Filesystem Maintenance](#filesystem-maintenance)
- [Cloud-Init Templates](#cloud-init-templates)

## Storage Management

### Add Storage to VM

Mount physical disk to virtual machine:

```bash
# 1. List available disks and UUIDs
blkid -o list

# 2. Add disk to VM by UUID
qm set <VMID> -sata1 /dev/disk/by-uuid/<UUID>
```

**Example:**
```bash
qm set 109 -sata1 /dev/disk/by-uuid/a1b2c3d4-e5f6-7890-abcd-ef1234567890
```

### Add Mount Point to LXC Container

#### Method 1: Edit Config File

```bash
# 1. Edit container config
nano /etc/pve/lxc/<CTID>.conf

# 2. Add mount point line
mp0: /mnt/host/path,mp=/mnt/container/path
```

#### Method 2: CLI Command

```bash
pct set <CTID> -mp0 volume=/mnt/host/path,mp=/mnt/container/path
```

**Example:**
```bash
pct set 110 -mp0 volume=/mnt/pve/share,mp=/mnt/shared
```

**Notes:**
- Host path must exist before mounting
- Container must be stopped to add mount points
- Multiple mount points use `mp0`, `mp1`, `mp2`, etc.

### Prepare External Disk Drive

Complete workflow for adding external storage to Proxmox:

#### 1. Unmount Disk

```bash
umount /dev/sdX
```

#### 2. Wipe Disk

Use Proxmox UI: `Disks > Wipe Disk`

Or via CLI:
```bash
wipefs -a /dev/sdX
```

#### 3. Create Partition Table

```bash
fdisk /dev/sdX
```

In fdisk:
- `n` - New partition
- `p` - Primary partition
- Accept defaults for full disk
- `w` - Write and exit

#### 4. Format Partition

```bash
mkfs.ext4 /dev/sdX1
```

**Filesystem options:**
- `ext4` - General purpose, journaled
- `xfs` - Large files, better performance
- `btrfs` - Advanced features, snapshots

#### 5. Get Partition UUID

```bash
blkid -o list
```

#### 6. Create Mount Point

```bash
mkdir -p /mnt/backups
```

#### 7. Add to fstab

```bash
nano /etc/fstab
```

Add line:
```
/dev/disk/by-uuid/<UUID> /mnt/backups ext4 defaults 0 2
```

**fstab columns:**
1. Device - Use UUID for stability
2. Mount point - Where to mount
3. Filesystem type - ext4, xfs, etc.
4. Options - `defaults` is usually sufficient
5. Dump - `0` (no backup)
6. Pass - `2` (fsck order, 0=skip)

#### 8. Mount All filesystems

```bash
mount -a
systemctl daemon-reload
```

#### 9. Verify Mount

```bash
df -h | grep backups
```

#### 10. Add to Proxmox Storage

UI: `Datacenter > Storage > Add > Directory`
- ID: `backups`
- Directory: `/mnt/backups`
- Content: Select desired types (VZDump, Images, etc.)

#### 11. Configure Backup Job

UI: `Datacenter > Backup > Add`
- Storage: `backups`
- Schedule: Configure as needed
- Selection mode: Choose VMs/containers

## VM Operations

### Resize VM Disk

Expand VM disk space:

```bash
qm resize <VMID> <disk> <size>
```

**Example:**
```bash
qm resize 100 scsi0 +20G
```

After expanding disk, resize partition inside VM (see [Linux Guide](./linux.md#resize-lvm-partition)).

## LXC Container Operations

### Container Filesystem Check

Repair corrupted container filesystem:

```bash
pct stop <CTID>
pct fsck <CTID>
pct start <CTID>
```

**Use when:**
- Container won't start
- Filesystem errors in logs
- After unexpected host shutdown

### Container Backup

```bash
vzdump <CTID> --storage <storage-id>
```

**Example:**
```bash
vzdump 110 --storage backups --mode snapshot
```

## Filesystem Maintenance

### Fix Corrupted Filesystem

For physical disks after power failure:

```bash
# 1. Unmount filesystem
umount /dev/sdXY

# 2. Run filesystem check and auto-fix
fsck.ext4 -y /dev/sdXY

# 3. Remount
mount /dev/sdXY
```

**Filesystem check tools:**
- `fsck.ext4` - ext4 filesystems
- `xfs_repair` - XFS filesystems
- `btrfs check` - Btrfs filesystems

**Symptoms of corruption:**
```
ls: cannot access 'file': Input/output error
-????????? ? ? ? ? file.txt
```

## Cloud-Init Templates

### Create Debian Cloud-Init Template

Automated VM template creation with cloud-init support:

```bash
# 1. Download Debian cloud image
wget https://cdimage.debian.org/images/cloud/bullseye/latest/debian-11-generic-amd64.raw

# 2. Create VM
qm create 5001 \
  --name debian-cloud \
  --net0 virtio,bridge=vmbr0 \
  --scsihw virtio-scsi-pci \
  --machine q35

# 3. Import disk
qm set 5001 \
  --scsi0 local-zfs:0,discard=on,ssd=1,format=raw,import-from=/root/debian-11-generic-amd64.raw

# 4. Resize disk
qm disk resize 5001 scsi0 8G

# 5. Configure boot
qm set 5001 --boot order=scsi0

# 6. Set CPU and RAM
qm set 5001 --cpu host --cores 2 --memory 4096

# 7. Configure UEFI
qm set 5001 \
  --bios ovmf \
  --efidisk0 local-zfs:1,format=raw,efitype=4m,pre-enrolled-keys=1

# 8. Add cloud-init drive
qm set 5001 --ide2 local-zfs:cloudinit

# 9. Enable QEMU guest agent
qm set 5001 --agent enabled=1

# 10. Customize cloud-init settings
# Use Proxmox UI: VM > Cloud-Init tab
# Set user, password, SSH keys, network config

# 11. Convert to template
qm template 5001
```

### Using the Template

```bash
# 1. Clone template (full clone recommended)
qm clone 5001 100 --name my-vm --full

# 2. Start VM
qm start 100

# 3. After first boot, install guest agent
sudo apt update
sudo apt install -y qemu-guest-agent
sudo reboot
```

**Template benefits:**
- Consistent base configuration
- Fast VM deployment
- Pre-configured cloud-init
- Standardized disk layout

## Best Practices

1. **Always use UUIDs** in fstab instead of device names (`/dev/sdX`)
2. **Test backups** by restoring to test VM/container
3. **Stop containers** before filesystem checks
4. **Regular snapshots** before major changes
5. **Monitor disk usage** - Set up alerts at 80% capacity
6. **Document custom configs** - Track changes to `/etc/pve/`
7. **Cloud-init templates** - One template per OS/version
8. **Label storage** clearly - Distinguish local/shared/backup storage

## Troubleshooting

### Container Won't Start

```bash
# Check logs
journalctl -u pve-container@<CTID>

# Check filesystem
pct fsck <CTID>

# Check mount points
cat /etc/pve/lxc/<CTID>.conf
```

### Storage Full

```bash
# Check usage
df -h
du -sh /var/lib/vz/images/*

# Remove old backups
find /mnt/backups -name "*.vma.zst" -mtime +30 -delete
```

### Mount Point Issues

```bash
# Verify host path exists
ls -la /mnt/host/path

# Check permissions
chmod 755 /mnt/host/path
chown root:root /mnt/host/path

# Restart container
pct stop <CTID> && pct start <CTID>
```

## See Also

- [Linux Guide](./linux.md) - Disk and filesystem operations
- [Docker Guide](./docker.md) - Container management
- [Proxmox Documentation](https://pve.proxmox.com/pve-docs/)
