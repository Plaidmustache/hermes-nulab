# Hermes-Nulab Deployment Handoff

You're taking over a local hermes-agent setup that's ready to push to GitHub and deploy on Coolify. Here's everything you need to know.

## What We Built

A fully configured Hermes Agent stack running locally in Docker with four services:

| Service | Container | Port | What it does |
|---------|-----------|------|-------------|
| **Gateway** | `hermes-nulab` | 18642 | The core Hermes agent. Uses DeepSeek V4 Flash. Custom Dockerfile extends base image with hindsight-client pre-installed. |
| **WebUI** | `hermes-nulab-webui` | 8787 | Browser chat interface. Uses pre-built image from ghcr.io. Custom notification sound and messages.js mounted. |
| **OpenPass** | `hermes-nulab-openpass` | 8788 | Encrypted credential manager. Self-contained Dockerfile downloads binary from GitHub releases. Hermes accesses via MCP. |
| **Hindsight** | `hermes-nulab-hindsight` | 8888 (API), 9999 (UI) | Long-term memory backend. Pre-built image from ghcr.io. Uses DeepSeek for entity extraction and memory synthesis. |

The agent's name is **Soren Vos**. Its personality (SOUL.md), memory backend, and credential manager are all configured.

## Key Files

### Infrastructure (our additions)
- `docker-compose.override.yml` — Full deployment config. Overrides the base `docker-compose.yml` with local isolation (uses `./.hermes-data/` instead of `~/.hermes/`). All services defined here.
- `Dockerfile.gateway` — Extends `nousresearch/hermes-agent:latest` with `hindsight-client` pre-installed.
- `Dockerfile.openpass` — Self-contained build that downloads OpenPass binary from GitHub releases v2.1.0. No Go toolchain needed.
- `COOLIFY_ENV.txt` — Reference for all environment variables needed on Coolify.
- `patches/hindsight-plugin-patched.py` — Patched Hindsight plugin that adds tag filtering to recall/reflect tools. Mounted as volume over the built-in plugin.
- `webui-static/notification.ogg` — Custom chiptune notification sound.
- `webui-static/messages.js` — Modified to play the .ogg file instead of a synthetic beep.
- `docs/hermes-webui-setup.md` — Reference doc for webui deployment.
- `docs/hermes-hindsight-setup.md` — Reference doc for Hindsight memory setup.

### Agent configuration (persisted in `./.hermes-data/`)
- `config.yaml` — Model, memory provider, MCP servers, agent settings
- `hindsight/config.json` — Hindsight connection config (local_external mode)
- `.openpass/config.yaml` — Agent permissions for credential access
- `.openpass/mcp-token` — Bearer token for OpenPass MCP auth
- `SOUL.md` — Soren Vos personality definition
- `.env` — Secrets (API keys, passphrases, tokens) — GITIGNORED

### Obsidian runbooks (documentation)
Three runbooks in the Obsidian vault at `00-Quick Reference/*Hermes-nulab-runbook/`:
- `hermes-web-ui-setup.md` — WebUI deployment guide with all gotchas
- `hindsight-memory-setup.md` — Hindsight memory backend setup
- `openpass-credential-manager-setup.md` — OpenPass credential manager setup

## Environment Variables for Coolify

Set these in Coolify's service environment variables for the gateway service:

```
DEEPSEEK_API_KEY=sk-...              # Required — DeepSeek API key
OPENPASS_PASSPHRASE=...              # Required — clean alphanumeric, no / + =
OPENPASS_MCP_TOKEN=...               # Required — must match vault's mcp-token
GATEWAY_ALLOW_ALL_USERS=true         # Required — allows access to gateway
HERMES_UID=1000                      # Linux default UID
HERMES_GID=1000                      # Linux default GID
```

The current values are in `.env` in the project root (gitignored, not pushed). Read them from there.

## Architecture Notes

### Inter-service communication
All services use `network_mode: bridge` with `host.docker.internal` for cross-container communication. The gateway has `extra_hosts: host.docker.internal:host-gateway` to make this work on Linux (Coolify runs on Linux, not macOS).

### Data persistence
All persistent data is in `./.hermes-data/`:
- Gateway: config, sessions, skills, memory
- OpenPass: encrypted vault (`.openpass/`)
- Hindsight: PostgreSQL data (`hindsight-data/`)

This directory is gitignored (contains secrets). It must be present on the VPS. The existing data there has been tested and works.

### The notification sound
The webui's notification sound is a Web Audio API oscillator by default. We replaced it with a custom .ogg file. The files are mounted at `/apptoo/static/` (NOT `/app/static/`) because the webui's init script rsyncs from `/apptoo/` to `/app/` at startup, overwriting anything at `/app/static/`.

## Before Pushing

1. The `.env` file in the project root is gitignored — secrets won't be pushed. ✅
2. The `.hermes-data/` directory is gitignored — sessions/config won't be pushed. ✅
3. Build artifacts (`build/`) are gitignored. ✅
4. All Dockerfiles are self-contained — no absolute paths to local machines. ✅

## Known Gotchas Deployed With

1. **host.docker.internal** — Works on macOS Docker Desktop natively. On Linux (Coolify), needs `extra_hosts: host.docker.internal:host-gateway` which we've added.
2. **MCP token** — Hardcoded in `config.yaml` because Hermes doesn't resolve `env:VAR` syntax in headers. Must match the vault's `mcp-token` file.
3. **OpenPass passphrase** — Must be clean alphanumeric. Special characters (`/`, `+`, `=`) break env var parsing.
4. **Hindsight plugin patch** — Soren (the agent) modified the Hindsight plugin to add tag filtering. The patched file is mounted as a volume. Without it, tag filtering on recall/reflect doesn't work.
5. **WebUI init rsync** — The webui container runs `rsync /apptoo/ → /app/` at startup. Custom files must be mounted at `/apptoo/`, not `/app/`.
6. **Gateway venv persistence** — The `hindsight-client` is baked into the Docker image via `Dockerfile.gateway`. No runtime install needed.
7. **DeepSeek model name** — Using `deepseek-v4-flash` (the current name; `deepseek-chat` is deprecated).
8. **WANTED_UID/WANTED_GID** — Default to 501/20 (macOS). On Linux, set to 1000/1000 via Coolify env vars.

## What To Do

1. Read through the files above to understand the setup
2. Check the current `.env` for the actual secret values
3. Push to GitHub
4. Configure Coolify with the env vars from COOLIFY_ENV.txt
5. Deploy
6. Verify: curl http://<vps-ip>:8787 should return 302 (webui login)
