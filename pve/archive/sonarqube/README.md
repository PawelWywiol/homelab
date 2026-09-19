# SonarQube

## Troubleshooting

`bootstrap check failure [1] of [1]: max virtual memory areas vm.max_map_count [65530] is too low, increase to at least [262144]`

Log in into your server and run the following command:

```bash
sudo sysctl -w vm.max_map_count=262144
```