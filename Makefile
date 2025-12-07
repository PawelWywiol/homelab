.PHONY: help pull push

help:
	@echo " "
	@echo "File Sync Makefile"
	@echo " "
	@echo "Usage:"
	@echo "  make pull NAME - Pull files from remote server to ./pve/NAME"
	@echo "  make push NAME - Push files from ./pve/NAME to remote server"
	@echo " "
	@echo "Examples:"
	@echo "  make pull x202  - Pulls from remote to ./pve/x202"
	@echo "  make push x202  - Pushes from ./pve/x202 to remote"
	@echo " "
	@echo "Note: NAME must match an existing directory in ./pve/"
	@echo "      Remote host is configured in ./pve/NAME/.envrc"
	@echo " "

pull:
	@if [ -z "$(word 2, $(MAKECMDGOALS))" ]; then \
		echo "Usage: make pull NAME"; \
		exit 1; \
	fi; \
	./scripts/sync-files.sh pull "$(word 2, $(MAKECMDGOALS))"

push:
	@if [ -z "$(word 2, $(MAKECMDGOALS))" ]; then \
		echo "Usage: make push NAME"; \
		exit 1; \
	fi; \
	./scripts/sync-files.sh push "$(word 2, $(MAKECMDGOALS))"

# Prevent arguments from being treated as targets
%:
	@:
