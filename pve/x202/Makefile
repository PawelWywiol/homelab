.PHONY: help
help:
	@echo " "
	@echo "Makefile for managing development environment"
	@echo "Available targets:"
	@echo " "
	@echo "- Generic app management:"
	@echo " "
	@echo "  make APP [up|down|restart|pull|logs] - Manage any app in docker/config/"
	@echo "    Examples: make caddy up, make portainer down, make redis logs"
	@echo " "
	@echo "- Special commands:"
	@echo " "
	@echo "  postgres [add|remove] DB_NAME - Manage PostgreSQL databases"
	@echo "  glitchtip createsuperuser - Create GlitchTip admin user"
	@echo " "
	@echo "- Tools:"
	@echo " "
	@echo "  k6-build - Build k6 with custom outputs"
	@echo "  k6-grafana SCRIPT - Run k6 tests with Grafana output"
	@echo "  k6-dashboard SCRIPT - Run k6 tests and export dashboard"
	@echo "  random - Generate a random hex string"
	@echo " "

# Special commands defined first to override generic pattern
.PHONY: postgres
postgres:
	@case "$(word 2, $(MAKECMDGOALS))" in \
		up) docker compose --env-file ./docker/config/postgres/.env -f ./docker/config/postgres/compose.yml up -d ;; \
		down) docker compose -f ./docker/config/postgres/compose.yml down ;; \
		restart) docker compose -f ./docker/config/postgres/compose.yml restart ;; \
		pull) docker compose -f ./docker/config/postgres/compose.yml pull ;; \
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
		*) echo "Usage: make postgres [up|down|restart|pull|add|remove]"; exit 1 ;; \
	esac

.PHONY: glitchtip
glitchtip:
	@case "$(word 2, $(MAKECMDGOALS))" in \
		up) docker compose --env-file ./docker/config/glitchtip/.env -f ./docker/config/glitchtip/compose.yml up -d ;; \
		down) docker compose -f ./docker/config/glitchtip/compose.yml down ;; \
		restart) docker compose -f ./docker/config/glitchtip/compose.yml restart ;; \
		pull) docker compose -f ./docker/config/glitchtip/compose.yml pull ;; \
		createsuperuser) docker compose -f ./docker/config/glitchtip/compose.yml run glitchtip-migrate ./manage.py createsuperuser ;; \
		*) echo "Usage: make glitchtip [up|down|restart|pull|createsuperuser]"; exit 1 ;; \
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

# Prevent action words from being treated as targets
.PHONY: up down restart pull logs add remove createsuperuser
up down restart pull logs add remove createsuperuser:
	@:

# Generic app management - catches all non-special targets
%:
	@# Skip if this is an argument to a special command (3+ goals means special command with args)
	@if [ "$(words $(MAKECMDGOALS))" -ge 3 ] && [ "$@" = "$(lastword $(MAKECMDGOALS))" ]; then \
		: ; \
	elif [ -f "./docker/config/$@/compose.yml" ]; then \
		ACTION="$(word 2, $(MAKECMDGOALS))"; \
		if [ -z "$$ACTION" ]; then \
			echo "Usage: make $@ [up|down|restart|pull|logs]"; exit 1; \
		fi; \
		case "$$ACTION" in \
			up) \
				if [ -f "./docker/config/$@/.env" ]; then \
					docker compose --env-file ./docker/config/$@/.env -f ./docker/config/$@/compose.yml up -d; \
				else \
					docker compose -f ./docker/config/$@/compose.yml up -d; \
				fi ;; \
			down) \
				docker compose -f ./docker/config/$@/compose.yml down ;; \
			restart) \
				docker compose -f ./docker/config/$@/compose.yml restart ;; \
			pull) \
				docker compose -f ./docker/config/$@/compose.yml pull ;; \
			logs) \
				docker compose -f ./docker/config/$@/compose.yml logs -f ;; \
			*) \
				echo "Invalid action '$$ACTION'. Use: up|down|restart|pull|logs"; exit 1 ;; \
		esac; \
	elif [ "$(word 2, $(MAKECMDGOALS))" = "" ]; then \
		: ; \
	else \
		echo "Error: App '$@' not found in ./docker/config/"; \
		echo "Available apps:"; \
		ls -1 ./docker/config/ 2>/dev/null | grep -v '^\.' || echo "  (none)"; \
		exit 1; \
	fi
