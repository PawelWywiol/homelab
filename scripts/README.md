# Scripts

Initialization and utility scripts for homelab setup.

## Available Scripts

**init-lxc.sh** - LXC container initialization
**init-vm.sh** - VM initialization
**sync-files.sh** - Bidirectional file sync (rsync wrapper)

## sync-files.sh

Synchronize files between local and remote systems using rsync.

**Usage:**

```bash
# Pull: Server -> Local
./scripts/sync-files.sh pull NAME

# Push: Local -> Server
./scripts/sync-files.sh push NAME
```

NAME must match a directory in `pve/` (x000, x201, x202, x250).

**Configuration:**

Each `pve/NAME/` directory must have a `.envrc` file with:

```bash
REMOTE_HOST="user@hostname"
REMOTE_FILES=(
  "file1"
  "dir/file2"
)
```

Copy `.envrc.example` to `.envrc` and set `REMOTE_HOST`.

## init-lxc.sh

Initialize LXC container with user setup and SSH access.

### On Container

Run the script, then reset `code` user password:

```bash
passwd code
```

### On Local Machine

**1. Remove previous SSH entry:**

```bash
ssh-keygen -R 192.168.0.XXX
```

**2. Add SSH key:**

```bash
ssh-copy-id code@192.168.0.XXX
```

**3. Update SSH config:**

```bash
nano ~/.ssh/config
```

```
Host local-host
  HostName 192.168.0.XXX
  User code
```

**4. Install ZSH (optional):**

```bash
# Install Oh My Zsh
sh -c "$(curl -fsSL https://install.ohmyz.sh)"

# Install Powerlevel10k theme
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git \
  "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"

# Install plugins
git clone https://github.com/zsh-users/zsh-autosuggestions \
  ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions

git clone https://github.com/zsh-users/zsh-syntax-highlighting.git \
  ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting

# Reload
source ~/.zshrc
```

## Tests

Test suite is located in `scripts/tests/`:

```bash
./scripts/tests/test-sync-makefile.sh
```
