# Windows Subsystem for Linux (WSL) Setup Guide

Complete guide for setting up WSL2 with Ubuntu, Docker, and SSH access from Windows host.

## Table of Contents

- [Installation](#installation)
- [Docker Setup](#docker-setup)
- [SSH Configuration](#ssh-configuration)
- [Network Configuration](#network-configuration)

## Installation

### Install WSL2

Enable WSL and install default Ubuntu distribution:

```powershell
# Run in PowerShell as Administrator
wsl --install
```

This command:
- Enables WSL and Virtual Machine Platform features
- Downloads and installs latest Ubuntu LTS
- Sets WSL2 as default version

**Manual installation:** See [Microsoft WSL Documentation](https://learn.microsoft.com/en-us/windows/wsl/install)

### Verify Installation

```powershell
wsl --list --verbose
```

Expected output:
```
  NAME      STATE           VERSION
* Ubuntu    Running         2
```

## Docker Setup

### Install Docker Desktop

Download and install from [Docker Desktop for Windows](https://docs.docker.com/desktop/setup/install/windows-install/)

**Requirements:**
- WSL2 backend enabled in Docker Desktop settings
- Windows 10/11 with WSL2

### Configure Docker Access

Add current user to docker group in WSL:

```bash
sudo usermod -aG docker $USER
```

**Log out and back in** to apply group membership.

Verify Docker access:

```bash
docker ps
```

Should run without `sudo`.

## SSH Configuration

### Install OpenSSH Server

Install and configure SSH daemon in WSL:

```bash
# Update package list
sudo apt update

# Install OpenSSH server
sudo apt install -y openssh-server

# Enable SSH service
sudo systemctl enable ssh
sudo systemctl start ssh
```

### Verify SSH Service

Check SSH server status:

```bash
sudo systemctl status ssh
```

Should show `active (running)`.

### Get Network Addresses

#### WSL IP Address

```bash
ip addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}'
```

Example output: `172.18.0.2`

#### Windows Host IP Address

**PowerShell Method 1:**
```powershell
Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias "vEthernet (WSL)"
```

**PowerShell Method 2:**
```powershell
ipconfig
```

Look for "vEthernet (WSL)" adapter.

**PowerShell Method 3:**
```powershell
netsh interface ipv4 show addresses
```

Example host IP: `192.168.1.100`

## Network Configuration

### Enable SSH Access from Windows Network

Configure port forwarding and firewall to allow external SSH connections to WSL.

#### Set Up Port Proxy

Forward port 22 from Windows host to WSL instance:

```powershell
# Run as Administrator
# Replace IPs with your actual addresses:
# - listenaddress: Windows host IP (192.168.x.x)
# - connectaddress: WSL IP (172.x.x.x)

netsh interface portproxy add v4tov4 `
  listenaddress=192.168.1.100 `
  listenport=22 `
  connectaddress=172.18.0.2 `
  connectport=22
```

**Note:** WSL IP changes on restart. For permanent solution, use startup script or static IP.

#### Verify Port Proxy

```powershell
netsh interface portproxy show all
```

#### Configure Windows Firewall

Allow inbound SSH connections:

```powershell
# Run as Administrator
New-NetFirewallRule `
  -DisplayName "WSL SSH" `
  -Direction Inbound `
  -Action Allow `
  -Protocol TCP `
  -LocalPort 22
```

#### Test SSH Connection

From another machine on network:

```bash
ssh username@192.168.1.100
```

Should connect to WSL instance.

### Remove Port Proxy (if needed)

```powershell
netsh interface portproxy delete v4tov4 `
  listenaddress=192.168.1.100 `
  listenport=22
```

## Best Practices

1. **Use SSH keys** instead of passwords for authentication
2. **Static IP** - Configure static IP for WSL to avoid port proxy updates
3. **Firewall rules** - Limit SSH access to specific IP ranges if possible
4. **Regular updates** - Keep WSL and packages updated:
   ```bash
   sudo apt update && sudo apt upgrade -y
   ```
5. **Backup WSL** - Export distributions regularly:
   ```powershell
   wsl --export Ubuntu C:\backup\ubuntu.tar
   ```

## Troubleshooting

### WSL Not Starting

```powershell
# Restart WSL
wsl --shutdown
wsl

# Check version
wsl --list --verbose

# Update WSL
wsl --update
```

### SSH Connection Refused

```bash
# Check SSH running
sudo systemctl status ssh

# Check port listening
sudo ss -tulpn | grep :22

# Restart SSH
sudo systemctl restart ssh
```

### Docker Permission Denied

```bash
# Verify group membership
groups

# Should include 'docker'
# If not, re-run usermod command and restart WSL
```

### Port Proxy Not Working

```powershell
# Check Windows Firewall
Get-NetFirewallRule -DisplayName "WSL SSH"

# Verify listening
netstat -an | Select-String "192.168.1.100:22"

# Check WSL IP changed
wsl hostname -I
```

## Automation Scripts

### Auto-Configure Port Proxy on Startup

Create PowerShell script (`wsl-ssh-proxy.ps1`):

```powershell
# Get WSL IP dynamically
$wslIP = (wsl hostname -I).Trim()
$hostIP = "192.168.1.100"  # Your Windows host IP

# Remove old proxy
netsh interface portproxy delete v4tov4 `
  listenaddress=$hostIP listenport=22 2>$null

# Add new proxy
netsh interface portproxy add v4tov4 `
  listenaddress=$hostIP `
  listenport=22 `
  connectaddress=$wslIP `
  connectport=22

Write-Host "Port proxy configured: $hostIP:22 -> $wslIP:22"
```

**Run on startup:**
- Task Scheduler > Create Basic Task
- Trigger: At startup
- Action: Start program `powershell.exe -ExecutionPolicy Bypass -File "C:\path\to\wsl-ssh-proxy.ps1"`
- Run with highest privileges

## See Also

- [Docker Guide](./docker.md) - Docker operations and best practices
- [Linux Guide](./linux.md) - Linux system administration
- [Microsoft WSL Documentation](https://learn.microsoft.com/en-us/windows/wsl/)
