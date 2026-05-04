# CLAUDE.md

> **AGENTS.md** is the upstream hermes-agent development guide (CLI internals, plugin system, testing). For **this project's deployment-specific rules**, read this file and the Obsidian runbooks.

## Deployment Workflow

This repo auto-deploys to Coolify on every push to `main`. **All infrastructure changes flow through git — never make ad-hoc fixes in Coolify or on the VPS directly.**

- Edit code here → push to `main` → GitHub webhook → Coolify builds and deploys
- Compose file for VPS: `docker-compose.coolify.yml` (uses compose networking, named volumes)
- Compose file for local: `docker-compose.override.yml` (Docker auto-merges it, uses bridge networking)
- Source of truth for deployment docs: Obsidian vault at `02-VPS Runbooks/Hermes-Nulab Coolify Deployment.md`

## J Code Munch

Use `jcodemunch` for code discovery before native file tools.

Start repository work by calling `resolve_repo` for the current directory. If the repo is not indexed, call `index_folder`.

Prefer:
- `search_symbols` for functions, classes, methods, and identifiers
- `search_text` for literals, comments, configs, and TODOs
- `get_repo_outline` and `get_file_tree` for structure
- `get_file_outline` before reading whole source files
- `get_symbol_source`, `get_context_bundle`, or `get_ranked_context` for targeted source context
- `index_file` after editing source files
