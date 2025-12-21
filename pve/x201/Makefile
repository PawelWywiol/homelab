.PHONY: help
help:
	@echo " "
	@echo "Makefile for x201 DNS/Network services"
	@echo " "
	@echo "Usage:"
	@echo "  make SERVICE [up|down|restart|pull|logs]"
	@echo "  make all [up|down]"
	@echo " "
	@echo "Services:"
	@echo "  caddy        - Reverse proxy with auto-HTTPS"
	@echo "  cloudflared  - Cloudflare tunnel"
	@echo "  pihole       - DNS + ad-blocking"
	@echo "  portainer    - Container management UI"
	@echo "  beszel-agent - System monitoring agent"
	@echo " "
	@echo "Examples:"
	@echo "  make caddy up"
	@echo "  make pihole logs"
	@echo "  make all up"
	@echo " "
	@echo "Tools:"
	@echo "  make random - Generate random hex string"
	@echo " "

.PHONY: random
random:
	@echo $(shell openssl rand -hex 32)

.PHONY: all
all:
	@ACTION="$(word 2, $(MAKECMDGOALS))"; \
	case "$$ACTION" in \
		up) \
			echo "Starting all services..."; \
			docker compose --env-file .env -f compose.yml up -d; \
			echo "All services started." ;; \
		down) \
			echo "Stopping all services..."; \
			docker compose -f compose.yml down; \
			echo "All services stopped." ;; \
		*) echo "Usage: make all [up|down]"; exit 1 ;; \
	esac

# Prevent action words from being treated as targets
.PHONY: up down restart pull logs
up down restart pull logs:
	@:

# Service management - uses single compose.yml with service-specific commands
.PHONY: caddy cloudflared pihole portainer beszel-agent
caddy cloudflared pihole portainer beszel-agent:
	@ACTION="$(word 2, $(MAKECMDGOALS))"; \
	if [ -z "$$ACTION" ]; then \
		echo "Usage: make $@ [up|down|restart|pull|logs]"; exit 1; \
	fi; \
	case "$$ACTION" in \
		up) \
			docker compose --env-file .env -f compose.yml up -d $@ ;; \
		down) \
			docker compose -f compose.yml stop $@ ;; \
		restart) \
			docker compose -f compose.yml restart $@ ;; \
		pull) \
			docker compose -f compose.yml pull $@ ;; \
		logs) \
			docker compose -f compose.yml logs -f $@ ;; \
		*) \
			echo "Invalid action '$$ACTION'. Use: up|down|restart|pull|logs"; exit 1 ;; \
	esac

# Catch unknown targets
%:
	@if [ "$(word 2, $(MAKECMDGOALS))" = "" ]; then \
		: ; \
	else \
		echo "Error: Unknown service '$@'"; \
		echo "Available services: caddy, cloudflared, pihole, portainer, beszel-agent"; \
		exit 1; \
	fi
