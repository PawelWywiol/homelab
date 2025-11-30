.PHONY: help
help:
	@echo " "
	@echo "Makefile for x199 control node services"
	@echo " "
	@echo "Usage:"
	@echo "  make APP [up|down|restart|pull|logs]"
	@echo " "
	@echo "Services:"
	@echo "  caddy     - Reverse proxy with auto-HTTPS"
	@echo "  semaphore - Ansible automation UI"
	@echo "  webhook   - GitHub webhook handler"
	@echo " "
	@echo "Examples:"
	@echo "  make caddy up"
	@echo "  make semaphore up"
	@echo "  make webhook logs"
	@echo " "
	@echo "Setup:"
	@echo "  make bootstrap - Run control node bootstrap"
	@echo "  make backup    - Backup control node"
	@echo "  make verify    - Verify backups"
	@echo " "
	@echo "Tools:"
	@echo "  make random - Generate random hex string"
	@echo " "

.PHONY: random
random:
	@echo $(shell openssl rand -hex 32)

.PHONY: bootstrap
bootstrap:
	./bootstrap.sh

.PHONY: backup
backup:
	./backup-control-node.sh

.PHONY: verify
verify:
	./verify-backups.sh

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
