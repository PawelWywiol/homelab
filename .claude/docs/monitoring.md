# Monitoring

## 2026-09-27 — Telegraf 1.38+ strict env var handling

Since 1.38.0, an unset `${VAR}` referenced anywhere in a config (e.g. inside
`interval = "${METRICS_INTERVAL}"`) fails parsing instead of substituting an
empty string; Telegraf just warns (`Strict environment variable handling is
the new default...`) and still runs fine once every referenced var is set.
Verified against 1.40.1 with `telegraf --test`: the warning appears whenever
`${VAR}` syntax is used, regardless of content, and is not itself an error.

**Action:** the env file (`/etc/default/telegraf`) must exist with every key
`base.conf`/fragments reference *before* `telegraf --config ... --test` runs.
`scripts/metrics-agent/install.sh` writes the full env file into its staging
dir and exports every value before calling `--test`, so this never bites.

## 2026-09-27 — `influxdb:1.x` init script runs once, on an empty volume only

The image's `init-influxdb.sh` entrypoint step creates `INFLUXDB_ADMIN_USER`,
`INFLUXDB_WRITE_USER`/`INFLUXDB_READ_USER` (with `GRANT WRITE`/`GRANT READ`)
and anything under `/docker-entrypoint-initdb.d/` (our `retention.sh`, which
does `CREATE RETENTION POLICY`) **only when the data volume is empty** (first
start, empty meta dir). Verified: `metrics-influxdb`'s `mi-smoke` smoke test
showed users/grants/RP created exactly once on a fresh volume.

**Action:** editing `INFLUXDB_WRITE_USER_PASSWORD` or `METRICS_RETENTION` in
`.env` after the volume already has data does nothing — the container never
re-runs init. Password/retention changes on a live instance need an admin
`influx` query (`SET PASSWORD`, `ALTER RETENTION POLICY ... DURATION ...`),
not a `.env` edit + restart. See `scripts/metrics-agent/README.md`.

## 2026-09-27 — Telegraf release tarballs ship only `.asc`, no `.sha256`

`dl.influxdata.com/telegraf/releases/telegraf-*.tar.gz` has a detached GPG
signature (`.asc`) next to it but no separate checksum file. Verify with gpg
against the pinned signing key fingerprint
(`24C975CBA61A024EE1B631787C3D57159FC2F927`), checking the **last field** of
the `--status-fd` `VALIDSIG` line (the primary key fingerprint per gpg's
documented format), not just that verification succeeded — a signature can
verify against a key that isn't the one you pinned.

## 2026-09-27 — `influxdb:latest` became InfluxDB 3 Core on 2026-09-15

The `latest` tag on Docker Hub switched from the 1.x line to InfluxDB 3 Core
on 2026-09-15 — a different product (72 h default query cap, fixed retention,
admin-only tokens, no InfluxQL users). Always pin an explicit tag
(`influxdb:1.13.1-alpine` here); never rely on `latest` for this image.

## 2026-09-27 — homepage's `services.yaml` cannot be parsed by plain `yaml.safe_load`

`python3 -c 'import yaml,sys;yaml.safe_load(open(sys.argv[1]))' \
pve/x000/docker/config/homepage/config/services.yaml` fails with
`ConstructorError: found unhashable key`, pre-existing and unrelated to any
particular edit (reproduces on `HEAD` before and after). Root cause: the
Pi-hole widget block uses Homepage's own `{{HOMEPAGE_VAR_PIHOLE_KEY}}`
templating, which PyYAML's safe loader parses as a flow-mapping key —
mappings aren't hashable, so construction fails at that line.

**Action:** don't use whole-file `yaml.safe_load` to validate a
`services.yaml` change. Extract and parse just the added/edited block instead.

## 2026-09-27 — x000 Caddy keeps serving the old Caddyfile after a deploy

`pve/x000/docker/config/caddy/compose.yml` mounts the Caddyfile as a single
file (`./Caddyfile:/etc/caddy/Caddyfile:ro`). A bind mount of a file pins its
inode; `git pull` writes a new file (new inode), and `docker compose up -d`
does not recreate an unchanged container, so the running Caddy keeps reading
the old file and a new route (e.g. `metrics.local.wywiol.eu`) never appears.

**Action:** after any Caddyfile change, run `make caddy restart` on x000
(`pve/x000/Makefile`: `down` then `up -d`, which recreates the container).
