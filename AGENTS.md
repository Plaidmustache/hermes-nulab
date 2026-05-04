# AGENTS.md

> **UPSTREAM_AGENTS.md** is the upstream hermes-agent development guide (CLI internals, plugin system, testing). For **this project's deployment-specific rules**, read this file and the Obsidian runbooks.

## Deployment Workflow

This repo auto-deploys to Coolify on every push to `main`. **All infrastructure changes flow through git — never make ad-hoc fixes in Coolify or on the VPS directly.**

- Edit code here → push to `main` → GitHub webhook → Coolify builds and deploys
- Compose file for VPS: `docker-compose.coolify.yml` (uses compose networking, named volumes)
- Compose file for local: `docker-compose.override.yml` (Docker auto-merges it, uses bridge networking)
- Source of truth for deployment docs: Obsidian vault at `02-VPS Runbooks/Hermes-Nulab Coolify Deployment.md`
