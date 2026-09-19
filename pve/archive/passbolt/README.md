# Passbolt

### Docs

[https://github.com/passbolt/passbolt_docker/](https://github.com/passbolt/passbolt_docker/)

### Admin

```shell
docker exec passbolt su -m -c "bin/cake passbolt register_user -u your@email.com -f yourname -l surname -r admin" -s /bin/sh www-data
```

### Sending test mail

```shell
docker exec -it passbolt bash
> ./bin/cake passbolt send_test_email --recipient=myemail@mydomain.com
```