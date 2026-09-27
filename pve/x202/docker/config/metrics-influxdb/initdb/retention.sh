# Sourced by the image's init-influxdb.sh on the first start only; $INFLUX_CMD is its admin client.
# Later changes: ALTER RETENTION POLICY "metrics_rp" ON "metrics" DURATION <d>
$INFLUX_CMD "CREATE RETENTION POLICY \"metrics_rp\" ON \"metrics\" DURATION ${METRICS_RETENTION:-90d} REPLICATION 1 DEFAULT"
