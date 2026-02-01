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

# Prevent action words from being treated as targets
.PHONY: up down restart pull logs add remove
up down restart pull logs add remove:
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
