# Wakapi

### Docs

[https://github.com/muety/wakapi](https://github.com/muety/wakapi)

### Env

Generate SLAT

```shell
SALT=$(cat /dev/urandom | LC_ALL=C tr -dc 'a-zA-Z0-9' | fold -w ${1:-32} | head -n 1)

echo "WAKAPI_PASSWORD_SALT=$SALT" > .env
```

### Admin

First user will be admin