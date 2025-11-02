.PHONY: help
help:
	@echo " "
	@echo "Makefile for managing development environment"
	@echo "Available targets:"
	@echo " "
	@echo "- containers:"
	@echo " "
	@echo "  caddy [up|down|restart] - Manage Caddy web server"
	@echo "  portainer [up|down|restart] - Manage Docker containers"
	@echo "  n8n [up|down|restart] - Manage n8n workflow automation tool"
	@echo "  wakapi [up|down|restart] - Manage Wakapi API usage tracking"
	@echo "  beszel [up|down|restart] - Manage Beszel API"
	@echo "  uptime-kuma [up|down|restart] - Manage Uptime Kuma"
	@echo "  ntfy [up|down|restart] - Manage NTFY notification service"
	@echo "  grafana [up|down|restart] - Manage Grafana"
	@echo "  postgres [up|down|restart] - Manage PostgreSQL database with pgAdmin"
	@echo "  redis [up|down|restart] - Manage Redis database"
	@echo "  mongo [up|down|restart] - Manage MongoDB database with Mongo Express"
	@echo "  influxdb [up|down|restart] - Manage InfluxDB database"
	@echo " "
	@echo "- tools:"
	@echo " "
	@echo "  k6-build - Build k6 with custom outputs"
	@echo "  k6-grafana - Run k6 tests with Grafana output"
	@echo "  k6-dashboard - Run k6 tests and export dashboard"
	@echo "  random - Generate a random hex string"
	@echo " "

.PHONY: caddy
caddy:
	@case "$(word 2, $(MAKECMDGOALS))" in \
		up) docker compose --env-file ./docker/config/caddy/.env -f ./docker/config/caddy/compose.yml up -d ;; \
		down) docker compose -f ./docker/config/caddy/compose.yml down ;; \
		restart) docker compose -f ./docker/config/caddy/compose.yml restart ;; \
		*) echo "Usage: make caddy [up|down|restart]"; exit 1 ;; \
	esac

.PHONY: portainer
portainer:
	@case "$(word 2, $(MAKECMDGOALS))" in \
		up) docker compose -f ./docker/config/portainer/compose.yml up -d ;; \
		down) docker compose -f ./docker/config/portainer/compose.yml down ;; \
		restart) docker compose -f ./docker/config/portainer/compose.yml restart ;; \
		*) echo "Usage: make portainer [up|down|restart]"; exit 1 ;; \
	esac

.PHONY: n8n
n8n:
	@case "$(word 2, $(MAKECMDGOALS))" in \
		up) docker compose --env-file ./docker/config/n8n/.env -f ./docker/config/n8n/compose.yml up -d ;; \
		down) docker compose -f ./docker/config/n8n/compose.yml down ;; \
		restart) docker compose -f ./docker/config/n8n/compose.yml restart ;; \
		*) echo "Usage: make n8n [up|down|restart]"; exit 1 ;; \
	esac

.PHONY: glitchtip
glitchtip:
	@case "$(word 2, $(MAKECMDGOALS))" in \
		up) docker compose --env-file ./docker/config/glitchtip/.env -f ./docker/config/glitchtip/compose.yml up -d ;; \
		down) docker compose -f ./docker/config/glitchtip/compose.yml down ;; \
		restart) docker compose -f ./docker/config/glitchtip/compose.yml restart ;; \
		createsuperuser) docker compose -f ./docker/config/glitchtip/compose.yml run glitchtip-migrate ./manage.py createsuperuser ;; \
		*) echo "Usage: make glitchtip [up|down|restart|createsuperuser]"; exit 1 ;; \
	esac

.PHONY: wakapi
wakapi:
	@case "$(word 2, $(MAKECMDGOALS))" in \
		up) docker compose --env-file ./docker/config/wakapi/.env -f ./docker/config/wakapi/compose.yml up -d ;; \
		down) docker compose -f ./docker/config/wakapi/compose.yml down ;; \
		restart) docker compose -f ./docker/config/wakapi/compose.yml restart ;; \
		*) echo "Usage: make wakapi [up|down|restart]"; exit 1 ;; \
	esac

.PHONY: sonarqube
sonarqube:
	@case "$(word 2, $(MAKECMDGOALS))" in \
		up) docker compose --env-file ./docker/config/sonarqube/.env -f ./docker/config/sonarqube/compose.yml up -d ;; \
		down) docker compose -f ./docker/config/sonarqube/compose.yml down ;; \
		restart) docker compose -f ./docker/config/sonarqube/compose.yml restart ;; \
		*) echo "Usage: make sonarqube [up|down|restart]"; exit 1 ;; \
	esac

.PHONY: beszel
beszel:
	@case "$(word 2, $(MAKECMDGOALS))" in \
		up) docker compose --env-file ./docker/config/beszel/.env -f ./docker/config/beszel/compose.yml up -d ;; \
		down) docker compose -f ./docker/config/beszel/compose.yml down ;; \
		restart) docker compose -f ./docker/config/beszel/compose.yml restart ;; \
		*) echo "Usage: make beszel [up|down|restart]"; exit 1 ;; \
	esac

.PHONY: uptime-kuma
uptime-kuma:
	@case "$(word 2, $(MAKECMDGOALS))" in \
		up) docker compose -f ./docker/config/uptime-kuma/compose.yml up -d ;; \
		down) docker compose -f ./docker/config/uptime-kuma/compose.yml down ;; \
		restart) docker compose -f ./docker/config/uptime-kuma/compose.yml restart ;; \
		*) echo "Usage: make uptime-kuma [up|down|restart]"; exit 1 ;; \
	esac

.PHONY: ntfy
ntfy:
	@case "$(word 2, $(MAKECMDGOALS))" in \
		up) docker compose --env-file ./docker/config/ntfy/.env -f ./docker/config/ntfy/compose.yml up -d ;; \
		down) docker compose -f ./docker/config/ntfy/compose.yml down ;; \
		restart) docker compose -f ./docker/config/ntfy/compose.yml restart ;; \
		*) echo "Usage: make ntfy [up|down|restart]"; exit 1 ;; \
	esac

.PHONY: grafana
grafana:
	@case "$(word 2, $(MAKECMDGOALS))" in \
		up) docker compose --env-file ./docker/config/grafana/.env -f ./docker/config/grafana/compose.yml up -d ;; \
		down) docker compose -f ./docker/config/grafana/compose.yml down ;; \
		restart) docker compose -f ./docker/config/grafana/compose.yml restart ;; \
		*) echo "Usage: make grafana [up|down|restart]"; exit 1 ;; \
	esac

.PHONY: postgres
postgres:
	@case "$(word 2, $(MAKECMDGOALS))" in \
		up) docker compose --env-file ./docker/config/postgres/.env -f ./docker/config/postgres/compose.yml up -d ;; \
		down) docker compose -f ./docker/config/postgres/compose.yml down ;; \
		restart) docker compose -f ./docker/config/postgres/compose.yml restart ;; \
		add) \
			if [ -z "$(word 3, $(MAKECMDGOALS))" ]; then \
				echo "Usage: make postgres add SOME_DB_NAME"; exit 1; \
			else \
				bash ./docker/config/postgres/init-db.sh $(word 3, $(MAKECMDGOALS)); \
			fi ;; \
		remove) \
			if [ -z "$(word 3, $(MAKECMDGOALS))" ]; then \
				echo "Usage: make postgres remove SOME_DB_NAME"; exit 1; \
			else \
				bash ./docker/config/postgres/remove-db.sh $(word 3, $(MAKECMDGOALS)); \
			fi ;; \
		*) echo "Usage: make postgres [up|down|restart|add|remove]"; exit 1 ;; \
	esac

.PHONY: redis
redis:
	@case "$(word 2, $(MAKECMDGOALS))" in \
		up) docker compose --env-file ./docker/config/redis/.env -f ./docker/config/redis/compose.yml up -d ;; \
		down) docker compose -f ./docker/config/redis/compose.yml down ;; \
		restart) docker compose -f ./docker/config/redis/compose.yml restart ;; \
		*) echo "Usage: make redis [up|down|restart]"; exit 1 ;; \
	esac

.PHONY: rabbitmq
rabbitmq:
	@case "$(word 2, $(MAKECMDGOALS))" in \
		up) docker compose --env-file ./docker/config/rabbitmq/.env -f ./docker/config/rabbitmq/compose.yml up -d ;; \
		down) docker compose -f ./docker/config/rabbitmq/compose.yml down ;; \
		restart) docker compose -f ./docker/config/rabbitmq/compose.yml restart ;; \
		*) echo "Usage: make rabbitmq [up|down|restart]"; exit 1 ;; \
	esac

.PHONY: mongo
mongo:
	@case "$(word 2, $(MAKECMDGOALS))" in \
		up) docker compose --env-file ./docker/config/mongo/.env -f ./docker/config/mongo/compose.yml up -d ;; \
		down) docker compose -f ./docker/config/mongo/compose.yml down ;; \
		restart) docker compose -f ./docker/config/mongo/compose.yml restart ;; \
		*) echo "Usage: make mongo [up|down|restart]"; exit 1 ;; \
	esac

.PHONY: influxdb
influxdb:
	@case "$(word 2, $(MAKECMDGOALS))" in \
		up) docker compose --env-file ./docker/config/influxdb/.env -f ./docker/config/influxdb/compose.yml up -d ;; \
		down) docker compose -f ./docker/config/influxdb/compose.yml down ;; \
		restart) docker compose -f ./docker/config/influxdb/compose.yml restart ;; \
		*) echo "Usage: make influxdb [up|down|restart]"; exit 1 ;; \
	esac

.PHONY: k6-build
k6-build:
	docker run --rm -u "$(id -u):$(id -g)" -v "${PWD}:/xk6" grafana/xk6 build \
  		--with github.com/grafana/xk6-output-influxdb \
  		--with github.com/grafana/xk6-dashboard

.PHONY: k6-grafana
k6-grafana:
	./k6 run -o xk6-influxdb=http://localhost:8086 $(addprefix ./docker/config/k6/scripts/,$(filter-out $@,$(MAKECMDGOALS)))

.PHONY: k6-dashboard
k6-dashboard:
	$(eval SCRIPT_NAME := $(filter-out $@,$(MAKECMDGOALS)))
	$(eval TIMESTAMP := $(shell date +%Y%m%d%H%M))
	./k6 run -o dashboard=export=./docker/data/k6/dashboards/$(SCRIPT_NAME)-$(TIMESTAMP).html ./docker/config/k6/scripts/$(SCRIPT_NAME).js

.PHONY: random
random:
	@echo $(shell openssl rand -hex 32)

%:
	@:
