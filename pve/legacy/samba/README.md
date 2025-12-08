# Samba

## Initial setup

```bash
docker exec -it samba bash
```

```bash
useradd pawel
passwd pawel
smbpasswd -a pawel
```

```bash
# check users
cat /etc/passwd
pdbedit --list --smbpasswd-style
```