# Linux System Administration Guide

Comprehensive reference for common Linux operations and system administration tasks.

## Table of Contents

- [File Operations](#file-operations)
- [Permissions Management](#permissions-management)
- [SSH Operations](#ssh-operations)
- [System Administration](#system-administration)
- [Text Processing](#text-processing)
- [Disk Management](#disk-management)

## File Operations

### File Synchronization

Synchronize files/directories between locations using rsync:

```bash
rsync -avP --no-perms --no-owner --no-group "$SRC_PATH/" "$DEST_PATH"
```

**Flags explained:**
- `-a` - Archive mode (preserves symlinks, modification times, recursive)
- `-v` - Verbose output
- `-P` - Show progress and keep partially transferred files
- `--no-perms` - Don't preserve permissions (useful for cross-system sync)
- `--no-owner` - Don't preserve owner
- `--no-group` - Don't preserve group

**Important:** Trailing slash on source (`SRC_PATH/`) syncs *contents* of directory. Without slash, syncs the directory itself.

### Remote Synchronization

#### Download from Remote

```bash
rsync -avPL --no-perms --no-owner --no-group user@host:~/source/ ./local/dest
```

#### Upload to Remote

```bash
rsync -avPL --no-perms --no-owner --no-group --update ./local/source user@host:~/dest
```

**Additional flags:**
- `-L` - Follow symlinks and copy actual files
- `--update` - Skip files newer on receiver

### Directory Size Analysis

Display sorted directory sizes (human-readable):

```bash
du -sh /path/to/directory/* | sort -rh
```

**Flags:**
- `-s` - Summary (total size only)
- `-h` - Human-readable (K, M, G)
- `sort -rh` - Reverse sort by human-readable numbers (largest first)

## Permissions Management

### Make File Executable

Grant execute permission:

```bash
chmod +x "$FILE"
```

Only for the owner:

```bash
chmod u+x "$FILE"
```

### Remove Execute Permission

```bash
chmod -x "$FILE"
```

### Recursive Permission Reset

Set standard permissions for web directories:

```bash
# Files: rw-r--r-- (644)
find /path/to/directory -type f -exec chmod 644 {} \;

# Directories: rwxr-xr-x (755)
find /path/to/directory -type d -exec chmod 755 {} \;
```

**Permission breakdown:**
- `644` - Owner: read/write, Group/Others: read only
- `755` - Owner: full, Group/Others: read/execute

## SSH Operations

### Remove Host from known_hosts

Required when IP address changes or after VM/container rebuild:

```bash
ssh-keygen -f "$HOME/.ssh/known_hosts" -R "192.168.1.100"
```

Replace with actual IP address or hostname.

### Copy SSH Key to Remote Host

Enable passwordless authentication:

```bash
ssh-copy-id user@host
```

Manually specify key:

```bash
ssh-copy-id -i ~/.ssh/id_ed25519.pub user@host
```

## System Administration

### Scheduled Restart

Configure automatic daily restart via cron:

```bash
sudo crontab -e
```

Add daily 2:30 AM restart:

```bash
30 2 * * * /sbin/shutdown -r now
```

**Cron syntax:** `minute hour day month weekday command`

### Check Disk Space

Display filesystem disk usage:

```bash
df -h
```

**Output columns:**
- Filesystem - Device/partition name
- Size - Total size
- Used - Space used
- Avail - Space available
- Use% - Percentage used
- Mounted on - Mount point

## Text Processing

### Multiline Echo

#### Basic multiline output:

```bash
echo -e "line1\nline2\nline3"
```

#### Heredoc with variable expansion:

```bash
cat <<EOF
line1
line2 with $VARIABLE expanded
line3
EOF
```

#### Heredoc without variable expansion:

```bash
cat <<'EOF'
line1
line2 with $VARIABLE not expanded
EOF
```

**Key difference:** Single quotes (`'EOF'`) disable variable substitution.

## Disk Management

### Resize LVM Partition

Expand partition to use all available space without data loss:

```bash
# 1. Check volume group
sudo vgdisplay

# 2. Extend logical volume to use 100% free space
sudo lvextend -l +100%FREE /dev/ubuntu-vg/ubuntu-lv

# 3. Resize filesystem to match
sudo resize2fs /dev/ubuntu-vg/ubuntu-lv
```

**Steps explained:**
1. `vgdisplay` - Shows volume groups and available space
2. `lvextend` - Extends the logical volume size
3. `resize2fs` - Grows the ext4 filesystem to fill the volume

**Note:** For XFS filesystems, use `xfs_growfs` instead of `resize2fs`.

### Verify Disk Space After Resize

```bash
df -h
```

Should show increased space on the resized partition.

## Best Practices

1. **Always test rsync** with `--dry-run` flag before actual sync
2. **Backup before permission changes** - Wrong permissions can break services
3. **Use SSH keys** instead of passwords for automation and security
4. **Monitor disk space** - Set up alerts before partitions fill
5. **Document cron jobs** - Add comments explaining what each job does
6. **Test LVM operations** in non-production first

## See Also

- [Docker Guide](./docker.md) - Container operations
- [Proxmox Guide](./proxmox.md) - VM and LXC management
- [WSL Guide](./wsl.md) - Windows Subsystem for Linux setup
