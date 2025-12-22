.PHONY: help
help:
	@echo " "
	@echo "Makefile for x000 control node services"
	@echo " "
	@echo "Usage:"
	@echo "  make APP [up|down|restart|pull|logs]"
	@echo " "
	@echo "Services:"
	@echo "  caddy       - Reverse proxy with auto-HTTPS"
	@echo "  webhook     - GitHub webhook handler"
	@echo "  portainer   - Container management UI"
	@echo "  cloudflared - Cloudflare tunnel"
	@echo "  pihole      - DNS + ad-blocking"
	@echo " "
	@echo "Examples:"
	@echo "  make caddy up"
	@echo "  make webhook up"
	@echo "  make webhook logs"
	@echo " "
	@echo "Setup:"
	@echo "  make setup     - Run control node setup"
	@echo "  make backup    - Backup control node"
	@echo "  make verify    - Verify backups"
	@echo " "
	@echo "Bulk:"
	@echo "  make all up    - Start all services"
	@echo "  make all down  - Stop all services"
	@echo " "
	@echo "Tools:"
	@echo "  make random - Generate random hex string"
	@echo " "

.PHONY: random
random:
	@echo $(shell openssl rand -hex 32)

.PHONY: setup
setup:
	./setup.sh

.PHONY: backup
backup:
	./backup-control-node.sh

.PHONY: verify
verify:
	./verify-backups.sh

.PHONY: all
all:
	@ACTION="$(word 2, $(MAKECMDGOALS))"; \
	case "$$ACTION" in \
		up) \
			echo "Starting all services..."; \
			$(MAKE) caddy up && \
			$(MAKE) webhook up && \
			$(MAKE) portainer up && \
			$(MAKE) cloudflared up && \
			$(MAKE) pihole up && \
			echo "All services started." ;; \
		down) \
			echo "Stopping all services..."; \
			$(MAKE) pihole down; \
			$(MAKE) cloudflared down; \
			$(MAKE) portainer down; \
			$(MAKE) webhook down; \
			$(MAKE) caddy down; \
			echo "All services stopped." ;; \
		*) echo "Usage: make all [up|down]"; exit 1 ;; \
	esac

# Prevent action words from being treated as targets
.PHONY: up down restart pull logs
up down restart pull logs:
	@:

# Generic app management
%:
	@if [ -f "./docker/config/$@/compose.yml" ]; then \
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
				docker compose -f ./docker/config/$@/compose.yml down && \
				if [ -f "./docker/config/$@/.env" ]; then \
					docker compose --env-file ./docker/config/$@/.env -f ./docker/config/$@/compose.yml up -d; \
				else \
					docker compose -f ./docker/config/$@/compose.yml up -d; \
				fi ;; \
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
