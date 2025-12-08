include .env .env.local
export

.PHONY: build
build:
	docker run --rm -u "$(id -u):$(id -g)" -v "${PWD}:/xk6" grafana/xk6 build \
  		--with github.com/grafana/xk6-output-influxdb \
  		--with github.com/grafana/xk6-dashboard