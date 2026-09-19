# Gotchas

## 2026-09-19 — init-host.sh via `curl | bash` loses its script directory

**Problem:** `scripts/init-host.sh` resolves `SCRIPT_DIR` from `${BASH_SOURCE[0]}`.
When piped to bash, `BASH_SOURCE[0]` is empty, so `dirname ""` → `.` and
`SCRIPT_DIR` becomes the **current working directory**, not the script location.

**Consequences (verified):**
- `.env` is sourced from `$PWD/.env` — the repo's `scripts/.env` is never read.
- `setup_version_switcher` can't find `$SCRIPT_DIR/init-host/Makefile` and silently
  falls back to the inline heredoc version.
- Exported env vars do NOT configure the script: `USERNAME="code"` etc. are assigned
  unconditionally at the top, before `.env` is sourced.

**Action:** for anything needing `.env` or the Makefile template, download the script
and run the local copy. Pipe mode is for defaults only.

## 2026-09-19 — `curl | bash` swallows script flags

`curl ... | sudo bash --install-node` → `bash: --install-node: invalid option`.
Bash parses them as its own options. Must use `bash -s -- --install-node`.

## 2026-09-19 — root requirements are inverted between the two setup scripts

- `scripts/init-host.sh` → **requires root** (`run_as_root`, exits 1 otherwise).
  `--help` is parsed before the check, so it works unprivileged.
- `pve/x000/setup.sh:72` → **refuses root** ("Do not run as root. Script uses sudo when needed.").

Easy to mix up; both are now stated in CLAUDE.md.

## 2026-09-19 — archiving a service triggers a container stop

Moving a dir out of `pve/xNNN/docker/config/` shows up as *removed* files in the
GitHub push payload. `trigger-homelab.sh` maps that to `stop-service.sh` and kills
the container on the host. Usually wanted — just not obvious.

Paths under `pve/archive/` match no routing prefix, so archived content is inert.

## 2026-09-19 — installers that live under $HOME must not run as root

`claude.ai/install.sh` puts everything under `$HOME`. It refuses `sudo` from a
user shell (`id -u` 0 **and** `SUDO_USER` set), but plain root — which is what
`init-host.sh` is — passes that check and installs into `/root/.local/bin`,
where the user's shell never finds it. Run it through `run_as_user`.

`herdr.dev/install.sh` has the same shape: `INSTALL_DIR="${HERDR_INSTALL_DIR:-$HOME/.local/bin}"`.
Set `HERDR_INSTALL_DIR=/usr/local/bin` to get a system-wide binary.

Neither installer touches a zsh rc file, so `~/.local/bin` has to be added to
`PATH` separately — the Claude installer prints a `.bashrc` hint only.

## 2026-09-19 — verified on Debian 12 in a container

`herdr 0.9.1` (Arch workstation runs 0.8.2) starts on Debian 12's glibc, and
`herdr config check` returns `config: ok` for the shipped config on 0.9.1 — so
the `goto = "prefix+s"` override does not collide with a 0.9.x default.
Claude Code installed as `2.1.278` with the launcher symlinked into
`~/.local/share/claude/versions/`. Both installers are no-ops on a second run.

## 2026-09-19 — p10k without a config starts a wizard on every shell

Powerlevel10k installed but unconfigured runs the configuration wizard on each
interactive shell, and `zsh -ic` then never returns. Shipping `~/.p10k.zsh` is
what avoids it. The instant-prompt preamble must be **prepended** to `.zshrc`
(it has to run before anything writes to the terminal), while `source
~/.p10k.zsh` goes at the end — two different positions, so they are two
separate guarded edits, not one block.

## 2026-09-19 — x201 already existed as a host before it had a repo folder

`192.168.0.201` was serving OpenClaw (`:18789`) via a Caddy route and a homepage
entry long before `pve/x201/` was created. The old CLAUDE.md row `x201 |
OpenClaw` was therefore half-right: the host was real, only the managed folder
was missing. OpenClaw itself is still standalone — not deployed from this repo.

Before declaring an environment non-existent, grep `Caddyfile` and
`homepage/config/services.yaml` for its IP, not just `pve/`.

## 2026-09-19 — adding a host touches six places, not one

A new `pve/xNNN/` is inert until all of these are updated:

1. `ansible/inventory/hosts.yml` — host + `services_base_path`
2. `ansible/group_vars/all/vars.yml` — `compose_paths`
3. `webhook/scripts/trigger-homelab.sh` — arrays, `extract_service_xNNN`,
   a case in all three loops (added/modified/removed), DEPLOY/STOP flags,
   the early-exit guard, and the two execution blocks
4. `webhook/scripts/common.sh` — `deploy_xNNN` / `stop_xNNN` notification titles
5. `caddy/Caddyfile` — routes
6. `homepage/config/docker.yaml` + `services.yaml`

Miss #3's early-exit guard and the host deploys but the run reports "Ignored".
The Makefile needs nothing — it discovers services from `docker/config/`.
