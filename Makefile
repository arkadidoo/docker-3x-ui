-include .env

CONTAINER_NAME ?= 3xui_app
PANEL_PORT     ?= 2057

.DEFAULT_GOAL := help

.PHONY: help ssl up down restart update logs status url

help: ## Show available commands
	@echo "Usage: make <target>"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'
	@echo ""

ssl: ## Issue / renew SSL certificate (requires root)
	sudo ./setup_ssl.sh

up: ## Start the panel (first run generates the secret base path)
	./run.sh

down: ## Stop and remove the container
	docker compose down

restart: ## Restart the container
	docker restart $(CONTAINER_NAME)

update: ## Pull latest image and recreate the container
	docker compose pull
	docker compose up -d

logs: ## Tail container logs
	docker logs -f $(CONTAINER_NAME)

status: ## Show container status
	docker compose ps

url: ## Print the current panel URL
	@[ -f .panel_path ] || { echo "No .panel_path found — run 'make up' first."; exit 1; }
	@IP=$$(curl -4 -s --max-time 5 ifconfig.me 2>/dev/null || echo "YOUR_SERVER_IP"); \
	 echo "https://$$IP:$(PANEL_PORT)/$$(cat .panel_path)/"
