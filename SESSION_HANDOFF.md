# Session Handoff — Hermes-Nulab Coolify Deployment

## Current State: Operational

The full 5-container Hermes stack is deployed and running on Coolify (Netcup VPS, `hermes.nulab.cc`). Auto-deploy works: push to `main` branch of `Plaidmustache/hermes-nulab` → GitHub webhook → Coolify builds and deploys.

## Stack Architecture

| Container | Purpose | Port | Image |
|---|---|---|---|
| `gateway` | Hermes agent, DeepSeek V4 Flash, API server | 18642 (internal) | Built from `Dockerfile.gateway` |
| `webui` | Community browser chat (nesquena/hermes-webui) | 8787 (internal) | `ghcr.io/nesquena/hermes-webui:latest` |
| `webui_auth` | Caddy reverse proxy in front of webui | 8787:80 (public) | `caddy:2-alpine` |
| `openpass` | Encrypted credential vault via MCP | 8788 (internal) | Built from `Dockerfile.openpass` |
| `hindsight` | Long-term memory backend | 8888 (internal) | `ghcr.io/vectorize-io/hindsight:latest` |

All use Docker Compose native networking (service names: `gateway`, `webui`, `hindsight`, `openpass`). No `network_mode: bridge`, no `host.docker.internal`.

## Key Configuration Decisions

### Networking
We use Docker Compose networking, NOT bridge mode. Bridge mode fails on Linux (Coolify host) — services can't communicate. Services communicate by name (`hindsight:8888`, `openpass:8788`). No `extra_hosts` needed.

### Compose Files
- `docker-compose.yml` — upstream from nousresearch/hermes-agent. NOT used directly.
- `docker-compose.override.yml` — LOCAL DEV ONLY. Auto-merged by Docker. Bridge networking, localhost ports, `./.hermes-data/` bind mount.
- `docker-compose.coolify.yml` — COOLIFY VPS. Named volumes, compose networking, Caddy proxy. This is the deploy target.

### Gateway
Runs in API mode (not TUI). Override command in compose:
```yaml
command:
  - sh
  - -c
  - |
    /opt/hermes/.venv/bin/hermes config set model.provider "deepseek"
    /opt/hermes/.venv/bin/hermes config set model.default "deepseek-v4-flash"
    /opt/hermes/.venv/bin/hermes config set model.base_url "https://api.deepseek.com"
    /opt/hermes/.venv/bin/hermes config set auxiliary.vision.model "glm-4.6v"
    /opt/hermes/.venv/bin/hermes config set auxiliary.vision.provider "zai"
    exec /opt/hermes/.venv/bin/hermes gateway run
```
The `hermes config set` commands write to config.yaml on the volume at startup. This is durable — survives deploys.

### WebUI
Uses the community webui image. Password via `HERMES_WEBUI_PASSWORD` env var (NOT pre-computed hash — signing key is per-instance). Himalaya email CLI installed at startup via entrypoint override. Workspace mounted as volume for persistence.

### Caddy
Pure reverse proxy on port 80 → `webui:8787`. NO basic auth — caused CORS issues with WebUI health check. WebUI handles its own auth via built-in password.

### OpenPass
Auto-initializes vault on first boot (`identity.age` check). Passphrase piped via `echo ... | openpass init`. Entrypoint overridden to `sh -c` for init script. MCP connection in gateway config.yaml uses service name `openpass:8788/mcp`.

### Hindsight
Separate long-term memory container. Plugin bundled with hermes-agent. Config at `hindsight/config.json` with `mode: local_external`, `api_url: http://hindsight:8888`. Both `HINDSIGHT_LLM_API_KEY` AND `HINDSIGHT_API_LLM_API_KEY` env vars needed (plugin and daemon use different names). Initializes lazily on first session.

### Vision
Z.AI vision via coding plan. Model: `glm-4.6v` (glm-5v-turbo not available on coding plan). Provider: `zai`. API key in Coolify env var `ZAI_API_KEY` — Hermes recognizes it (confirmed in `auth.py`: `api_key_env_vars=("GLM_API_KEY", "ZAI_API_KEY", "Z_AI_API_KEY")`). Endpoint auto-detected. Model changes need gateway restart (cached in process env vars at startup).

### Authentication
SINGLE layer: WebUI built-in password. We tried Caddy basic auth → removed because it broke the WebUI health check (login.js uses `credentials: omit` — Caddy 401 without CORS headers blocks it).

### Himalayas Email
CLI binary installed at webui startup via compose. Config at `/opt/data/home/.config/himalaya/config.toml` on the volume. Password retrieved from OpenPass MCP at runtime via helper script (`himalaya-openpass.sh`). Zero plaintext passwords in config files. Helper script calls OpenPass MCP, reads bearer token from config.yaml, fetches Infomaniak password.

### Credential Storage
Infomaniak device password stored in OpenPass vault at `email/soren.vos@ik.me`. OpenPass MCP tools available to agent (`mcp_openpass_list_entries`, `mcp_openpass_get_entry`, etc.). Email: `soren.vos@ik.me`, IMAP: `imap.infomaniak.com:993`, SMTP: `mail.infomaniak.com:587`.

## Resolved Issues

### 1. SOUL.md not loading
**Symptom:** Agent didn't know its persona. **Cause:** Volume permissions (UID mismatch — gateway runs as 501, webui as 1025). `/opt/data/` was 700, webui couldn't read SOUL.md. **Fix:** `chmod 755` on volume (see UNSOLVED below). Also: SOUL.md is injected as system prompt — agent doesn't know it's from a file. To verify it's loaded, ask "Describe your persona" not "What does your soul.md say."

### 2. WebUI "Cannot reach server" / login disabled
**Symptom:** Password field and sign-in button grayed out. **Cause:** Caddy basic auth + WebUI health check (`credentials: omit` in login.js). Caddy returns 401 without CORS headers → browser blocks the response → JS interprets as "server unreachable." **Fix:** Removed Caddy basic auth. WebUI uses built-in password only.

### 3. Hindsight not loading
**Symptom:** Agent used built-in memory (80/1,375 chars) instead of Hindsight. **Cause:** Volume permissions (same UID mismatch). WebUI creates AIAgent instances that can't read `hindsight/config.json`. **Fix:** `chmod 755` on volume.

### 4. Gateway in TUI mode
**Symptom:** No API server listening on port 18642. **Cause:** Default hermes-agent runs in TUI mode. **Fix:** Override command to `hermes gateway run` with model config.

### 5. OpenPass vault not initialized
**Symptom:** Container restarting, "vault not initialized" errors. **Cause:** Vault needs `openpass init`. **Fix:** Auto-init in startup command — check `identity.age`, pipe passphrase, use `--auth passphrase`. Note: check file is `identity.age` (not `identity.json`), passphrase must be piped via echo.

### 6. Agent-auth MCP server never connects
**Symptom:** Warnings about "agent-authenticator not found." **Cause:** Binary not installed, redundant with OpenPass. **Fix:** Removed from config.yaml. OpenPass handles TOTP + passwords.

### 7. Workspace files lost on deploy
**Symptom:** WebUI workspace at `/home/hermeswebui/workspace` emptied. **Cause:** That path is inside the container's ephemeral filesystem. **Fix:** Mounted named volume `hermes-workspace:/home/hermeswebui/workspace` in compose.

### 8. Coolify API quirks
- `POST /api/v1/services` creates service but no builds (no Dockerfiles)
- `POST /api/v1/applications/public` is the correct endpoint for dockercompose apps
- `/applications/{uuid}/deploy` → 404; use `/start` instead
- `start` = full deploy (clone + build), `restart` = restart only
- `docker_compose_raw` must be base64-encoded
- Env var PATCH: `{"key": "...", "value": "..."}` — single object, not array
- Git URL must have protocol prefix (`https://` or `git@`)

### 9. Service name hyphen issue
**Symptom:** WebUI init script crashed. **Cause:** Service `webui-auth` triggered `SERVICE_NAME_WEBUI-AUTH` — hyphen is invalid bash variable. **Fix:** Renamed to `webui_auth` (underscore).

### 10. Vision model plan restriction
**Symptom:** 429 "subscription does not include GLM-5V-Turbo." **Cause:** Coding plan doesn't include premium model. **Fix:** Switched to `glm-4.6v`. Env var changes need gateway restart (cached at process startup).

## Documentation

All docs are in the Obsidian vault and on the server:

### Obsidian Vault
- `02-VPS Runbooks/Hermes-Nulab Coolify Deployment.md` — full deployment guide (all sections)
- `02-VPS Runbooks/Hindsight Memory on Coolify.md` — Hindsight setup companion

### Git Repo
- `CLAUDE.md` / `AGENTS.md` — deployment workflow rules (both files have same content, serve different agent tools)
- `HERMES_NULAB_LOCAL.md` — local dev setup with compose file table
- `COOLIFY_ENV.txt` — env var reference
- `DEPLOYMENT_HANDOFF.md` — quick-start pointer to Obsidian
- `UPSTREAM_AGENTS.md` — original hermes-agent contributor guide (reference only)

### Server Skills (on volume, survive deploys)
- `/opt/data/skills/hermes-nulab-architecture/SKILL.md` — self-awareness skill (discovery-based, agent verifies live state)
- `/opt/data/skills/email/himalaya/SKILL.md` — Himalaya email setup with OpenPass credential pattern

## SOLVED: Volume Permissions Reset on Deploy

### The Problem
`/opt/data/` starts at mode 700 owned by UID 501 (gateway's `hermes` user). The WebUI container runs as UID 1025. The WebUI creates AIAgent instances directly and needs to read config files, SOUL.md, Hindsight config, etc. Without access: silent failures — agent ignores persona, uses built-in memory, can't access email config.

### Root Cause
The original entrypoint from `nousresearch/hermes-agent` (`/opt/hermes/docker/entrypoint.sh`) does:
1. As root: `usermod -u $HERMES_UID hermes`, `groupmod -o -g $HERMES_GID hermes`
2. As root: `chown -R hermes:hermes /opt/data`
3. As root: `chmod 640 /opt/data/config.yaml` ← makes config NOT world-readable
4. `exec gosu hermes "$0" "$@"` → drops to hermes user
5. As hermes: `mkdir -p /opt/data/{cron,sessions,logs,...}` — creates dirs with default umask (700)

The `chmod 640 config.yaml` and `mkdir` with default umask collectively make `/opt/data` and its contents unreadable by UID 1025 (webui).

### The Fix (Double-Fix Approach)
Two-layer defense in `docker-entrypoint-wrapper.sh` and compose `command:`:

**Layer 1 — Entrypoint wrapper** (`docker-entrypoint-wrapper.sh`):
```bash
#!/bin/sh
chmod 755 /opt/data
exec /opt/hermes/docker/entrypoint.sh "$@"
```
Runs as root BEFORE the original entrypoint. Sets `/opt/data` to 755.

**Layer 2 — Gateway CMD** (compose `command:`):
```yaml
command:
  - sh
  - -c
  - |
    /opt/hermes/.venv/bin/hermes config set model.provider "deepseek"
    /opt/hermes/.venv/bin/hermes config set model.default "deepseek-v4-flash"
    /opt/hermes/.venv/bin/hermes config set model.base_url "https://api.deepseek.com"
    /opt/hermes/.venv/bin/hermes config set auxiliary.vision.model "glm-4.6v"
    /opt/hermes/.venv/bin/hermes config set auxiliary.vision.provider "zai"
    chmod -R a+rX /opt/hermes
    chmod 755 /opt/data
    chmod 644 /opt/data/config.yaml 2>/dev/null || true
    exec /opt/hermes/.venv/bin/hermes gateway run
```
Runs AFTER `gosu` drops to hermes user. Works because the original entrypoint's `chown -R hermes:hermes /opt/data` makes hermes the **owner** — and owners can chmod their own files/dirs. The `chmod 644` overrides the entrypoint's `chmod 640` on config.yaml.

### Why This Works
- Layer 1 catches `/opt/data` perms before anything runs (root-level guarantee)
- Layer 2 catches both `/opt/data` perms AND `config.yaml` perms after the entrypoint finishes (owner-level chmod)
- The `2>/dev/null || true` handles first boot when config.yaml doesn't exist yet
- Both layers are idempotent and harmless

### What Didn't Work

1. **Host-level `sudo chmod 755`** — Docker user namespace remapping prevents container-visible permission changes.

2. **`chmod 755` in gateway CMD alone** — works for `/opt/data` but can't override the entrypoint's `chmod 640 config.yaml` (runs before gosu).

3. **Coolify post-deployment commands** — Coolify runs `docker exec {$container} {$cmd}` WITHOUT `-u root`, so chmod runs as the container's running user (hermes), which works for `/opt/data` but is a no-op for files owned by root. Also: only runs after deploy, not on container restart.

4. **Entrypoint wrapper alone** — can chmod `/opt/data` but the original entrypoint's `chmod 640 config.yaml` still overrides afterward.

### Verification
- **Commit**: `fbe51f97d` (both `docker-entrypoint-wrapper.sh` and `docker-compose.coolify.yml`)
- **Tested**: Triggered full redeploy via Coolify API on 2026-05-04. New containers created. Site healthy: API 401 (expected auth), webui 302 (login redirect). No manual `chmod` needed.

## Current State
All systems operational. Permissions fix is durable across deploys. Stack is maintenance-free — push to `main` triggers auto-deploy with correct permissions.

### Remaining Cleanup (Low Priority)
- **Dead post-deploy command**: Coolify still has `chmod 755 /opt/data` set as post-deployment command on gateway container. This is now a harmless no-op (gateway CMD already does it). Can be removed via Coolify browser UI when convenient — no MCP update tool exists.
- **Dead stack cleaned**: Old `hermes-agent` stack (UUID `y80os40s04wsogkk8wcokogk`) deleted from project 30.
