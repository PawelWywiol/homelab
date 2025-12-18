# Version Switcher Makefile
# Usage: make php74, make php83, make node20, make node22

.PHONY: help php74 php83 node20 node22 status

help:
	@echo "Version Switcher"
	@echo ""
	@echo "PHP versions:"
	@echo "  make php74    - Switch to PHP 7.4"
	@echo "  make php83    - Switch to PHP 8.3"
	@echo ""
	@echo "Node versions:"
	@echo "  make node20   - Switch to Node 20 LTS"
	@echo "  make node22   - Switch to Node 22"
	@echo ""
	@echo "Other:"
	@echo "  make status   - Show current versions"

status:
	@echo "Current versions:"
	@echo "  PHP:      $$(php -v 2>/dev/null | head -1 || echo 'not installed')"
	@echo "  Node:     $$(node -v 2>/dev/null || echo 'not installed')"
	@echo "  npm:      $$(npm -v 2>/dev/null || echo 'not installed')"
	@echo "  Composer: $$(composer -V 2>/dev/null | head -1 || echo 'not installed')"

php74:
	@echo "Switching to PHP 7.4..."
	@sudo update-alternatives --set php /usr/bin/php7.4
	@php -v | head -1

php83:
	@echo "Switching to PHP 8.3..."
	@sudo update-alternatives --set php /usr/bin/php8.3
	@php -v | head -1

node20:
	@echo "Switching to Node 20..."
	@fnm use 20 || fnm install 20
	@node -v

node22:
	@echo "Switching to Node 22..."
	@fnm use 22 || fnm install 22
	@node -v
