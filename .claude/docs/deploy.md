# Deploy (GitOps webhook)

## 2026-09-28 — every webhook deploy fails: host key verification

**Problem:** GitHub delivers the push (200, "processing"), but nothing deploys.
`docker logs webhook` on x000 shows `<host> deployment failed after 0s` for
every push since at least 2026-04-08 (x201, x202, x000 alike). x202's repo had
not pulled since 2026-04-09.

**Cause (verified):** `common.sh` `ssh_to_host` connects from the webhook
container to `code@host.docker.internal` (172.17.0.1) with
`StrictHostKeyChecking=accept-new` and `UserKnownHostsFile=~/.ssh/known_hosts`.
That file is the host's `~/.ssh/known_hosts` mounted **read-only**; it has no
entry for `host.docker.internal` or `172.17.0.1` (last modified 2026-04-06), and
accept-new cannot write to it → `Host key verification failed`.

**Also:** `trigger-homelab.sh` does `exit 1` when a host fails, so a failing x000
deploy blocks the x202/x201/x203 blocks after it.

**Action:** fix in the repo, not by hand on x000 (x000 is to be reworked to a
simpler deploy without OpenTofu/Ansible). Until then, deploy by hand on the
target: `cd ~/homelab && git pull && cd pve/xNNN && make SERVICE up`.
