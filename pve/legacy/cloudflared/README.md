# Cloudflare Zero Trust

## Documentation

[https://developers.cloudflare.com/cloudflare-one/connections/connect-devices/warp/set-up-warp/](https://developers.cloudflare.com/cloudflare-one/connections/connect-devices/warp/set-up-warp/)

## Access to private network

- create a new tunnel
  - add private network
  - configure access policy
- gateway
  - add firewall network policy
  - enable `DNS over HTTPS (DoH)` at dns locations DNS endpoints
- settings
  - network
    - enable firewall with TCP, UDP, and ICMP

## Troubleshooting

### CF_DNS_LOOKUP_FAILURE

#### Port 53 in use

```bash
sudo lsof -i :53
```

If Docker Desktop is using port 53, you can disable it in the Docker Desktop settings.

```bash
sed -i '' 's/"kernelForUDP": true/"kernelForUDP": false/' ~/Library/Group\ Containers/group.com.docker/settings.json
```

Then restart Docker Desktop (not only shutting down, but also starting it again).

### Cannot access to local network resources

[https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/private-net/connect-private-networks/](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/private-net/connect-private-networks/)

#### Check split tunneling

- settings > warp client > default device settings > split tunnels 
  - add private network CIDR and cloudflare account host

```bash
netstat -rn | grep 192.168
sudo route -n add -net 192.168.0.0/24 -interface utunX
```
