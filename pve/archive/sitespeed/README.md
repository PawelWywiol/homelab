# sitespeed.io

## Documentation

[https://www.sitespeed.io/documentation/sitespeed.io/](https://www.sitespeed.io/documentation/sitespeed.io/)

[Performance dashboard](https://www.sitespeed.io/documentation/sitespeed.io/performance-dashboard/)

## Prerequisites

### Proxmox - ifb module

#### Install ifb module if not already installed

```bash
ls /lib/modules/$(uname -r)/kernel/net/sched/ | grep ifb
```

```bash
sudo apt update
sudo apt install linux-modules-extra-$(uname -r)
```

#### Load ifb module

```bash
sudo modprobe ifb numifbs=1
```

#### Update lxc container config

```bash
pct stop XXX
```

```bash
nano /etc/pve/lxc/XXX.conf
```

```bash
lxc.apparmor.profile: unconfined
lxc.cgroup.devices.allow: c 10:200 rwm
lxc.mount.auto: cgroup:rw
lxc.cap.drop:
```

```bash
pct start XXX
```

## Install

### Check docker network list

```bash
docker network ls
```

### Start sitespeed.io container with dependencies

```bash
./up.sh
```

### Edit cron job for daily runs

```bash
crontab -e
```

add cron job to run every hour

```bash
0 * * * * /home/code/cron.sh > /dev/null 2>&1
```
