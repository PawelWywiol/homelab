.PHONY: help pull push

help:
	@echo " "
	@echo "File Sync Makefile"
	@echo " "
	@echo "Usage:"
	@echo "  make pull USER@HOST - Pull files from remote server to ./pve/HOST"
	@echo "  make push USER@HOST - Push files from ./pve/HOST to remote server"
	@echo " "
	@echo "Examples:"
	@echo "  make pull code@x202  - Pulls from code@x202 to ./pve/x202"
	@echo "  make push code@x202  - Pushes from ./pve/x202 to code@x202"
	@echo " "
	@echo "Note: HOST must match an existing directory in ./pve/"
	@echo " "

pull:
	@if [ -z "$(word 2, $(MAKECMDGOALS))" ]; then \
		echo "Usage: make pull USER@HOST"; \
		exit 1; \
	fi; \
	TARGET="$(word 2, $(MAKECMDGOALS))"; \
	HOST=$${TARGET##*@}; \
	if [ ! -d "./pve/$$HOST" ]; then \
		echo "Error: Host '$$HOST' not found in ./pve/"; \
		echo "Available hosts:"; \
		ls -1 ./pve/ 2>/dev/null | grep -v '^\.' || echo "  (none)"; \
		exit 1; \
	fi; \
	./scripts/sync-files.sh "$$TARGET" "./pve/$$HOST"

push:
	@if [ -z "$(word 2, $(MAKECMDGOALS))" ]; then \
		echo "Usage: make push USER@HOST"; \
		exit 1; \
	fi; \
	TARGET="$(word 2, $(MAKECMDGOALS))"; \
	HOST=$${TARGET##*@}; \
	if [ ! -d "./pve/$$HOST" ]; then \
		echo "Error: Host '$$HOST' not found in ./pve/"; \
		echo "Available hosts:"; \
		ls -1 ./pve/ 2>/dev/null | grep -v '^\.' || echo "  (none)"; \
		exit 1; \
	fi; \
	./scripts/sync-files.sh "./pve/$$HOST" "$$TARGET"

# Prevent arguments from being treated as targets
%:
	@:
