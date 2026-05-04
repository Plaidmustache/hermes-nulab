# Hermes WebUI — Setup Guide (alongside hermes-agent Docker deployment)

## 1. Prerequisites

- Existing hermes-agent running in Docker (gateway container)
- `hermes-nulab/docker-compose.override.yml` isolating state to `./.hermes-data/`
- `HERMES_HOME` inside the gateway container = `/opt/data`

## 2. Clone the WebUI repo

```bash
cd /Users/malone/Projects
git clone https://github.com/nesquena/hermes-webui.git --depth 1
```

## 3. Add the `webui` service to `docker-compose.override.yml`

```yaml
services:
  # ... existing gateway + dashboard services ...

  webui:
    build: /Users/malone/Projects/hermes-webui
    container_name: hermes-nulab-webui
    network_mode: bridge
    ports:
      - "127.0.0.1:8787:8787"
    volumes:
      - ./.hermes-data:/opt/data            # shared state (config, sessions, auth)
      - .:/opt/hermes-agent-src             # agent source — DO NOT nest under /opt/data!
    environment:
      - HERMES_WEBUI_HOST=0.0.0.0
      - HERMES_WEBUI_PORT=8787
      - HERMES_HOME=/opt/data
      - HERMES_WEBUI_STATE_DIR=/opt/data
      - HERMES_WEBUI_AUTO_INSTALL=1         # auto-install missing agent deps at startup
      - HERMES_WEBUI_AGENT_DIR=/opt/hermes-agent-src
      - WANTED_UID=501                      # macOS UID; use `id -u`
      - WANTED_GID=20                       # macOS GID; use `id -g`
      - DEEPSEEK_API_KEY=${DEEPSEEK_API_KEY:-}  # pass your provider API key
    depends_on:
      - gateway
```

## 4. Add 8787 port mapping to the `dashboard` service (optional)

```yaml
  dashboard:
    ports:
      - "127.0.0.1:19119:19119"
      - "127.0.0.1:8787:8787"     # <-- add this line
```

## 5. Rebuild and start

```bash
docker compose up -d --build webui
# or full stack:
docker compose up -d --build
```

## 6. Verify

```bash
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8787/
# Expected: 302 (redirect to login/setup page)
```

## Critical Pitfalls

### ❌ Pitfall 1: Nesting the agent source mount under the data volume

**Wrong:**
```yaml
volumes:
  - ./.hermes-data:/opt/data
  - .:/opt/data/hermes-agent     # NESTED — Docker resolves this to .hermes-data/hermes-agent/
```

**Right:**
```yaml
volumes:
  - ./.hermes-data:/opt/data
  - .:/opt/hermes-agent-src      # Separate top-level path — no conflict
```

**Why it fails:** Docker resolves nested bind mounts inside the first mount point's directory tree. If `.hermes-data/hermes-agent/` exists on the host, that directory shadows the intended source mount. The container sees stale pip build artifacts (`UNKNOWN.egg-info`, `build/`) instead of the actual source code. The agent fails to install, and any chat request throws `ModuleNotFoundError: No module named 'tools.checkpoint_manager'`.

**Cleanup if you hit this:**
```bash
sudo rm -rf ./.hermes-data/hermes-agent    # remove stale artifacts from data volume
rm -rf build/                               # remove stale artifacts from repo root
```

### ❌ Pitfall 2: Read-only source mount

**Wrong:**
```yaml
volumes:
  - .:/opt/hermes-agent-src:ro    # Read-only — pip can't write egg-info during install
```

**Right:**
```yaml
volumes:
  - .:/opt/hermes-agent-src       # Read-write — pip needs to write build artifacts
```

**Why it fails:** At startup, the webui runs `pip install /opt/hermes-agent-src` to install the agent into its venv. This requires writing `hermes_agent.egg-info/` to the source directory. A read-only mount causes `error: could not create 'hermes_agent.egg-info': Read-only file system`.

### ❌ Pitfall 3: Stale egg-info from previous install

After a successful `pip install`, `hermes_agent.egg-info/` and `build/` are left in the source tree. On the next container restart, pip sees the stale egg-info and fails with `Wheel has unexpected file name: expected 'hermes-agent', got 'unknown'`.

**Cleanup after each install (or before restart):**
```bash
rm -rf build/ hermes_agent.egg-info/
```

### ❌ Pitfall 4: Missing HERMES_WEBUI_AUTO_INSTALL

Without `HERMES_WEBUI_AUTO_INSTALL=1`, the webui detects missing agent modules (`dotenv`, etc.) but refuses to install them:
```
[!!] Auto-install disabled. Set HERMES_WEBUI_AUTO_INSTALL=1 to enable.
[!!] Still missing after install attempt: ['run_agent']
Agent features may not work correctly.
```

### ❌ Pitfall 5: Missing API key in the webui container

The gateway container has `DEEPSEEK_API_KEY` (or your provider's key), but the webui container does NOT inherit it automatically. You must pass it explicitly:

```yaml
environment:
  - DEEPSEEK_API_KEY=${DEEPSEEK_API_KEY:-}
```

Without this, chat requests fail with `RuntimeError: Provider 'deepseek' is set in config.yaml but no API key was found.`

### ❌ Pitfall 6: Wrong UID/GID for macOS

macOS UIDs start at 501, not 1000 (Linux default). Set `WANTED_UID` and `WANTED_GID` explicitly:

```bash
# Find yours:
id -u   # → 501
id -g   # → 20
```

Without this, the webui container's `hermeswebui` user can't read files written by the gateway container (and vice versa), causing permission errors on the shared `./.hermes-data` volume.

## Architecture Summary

```
┌─────────────────────────────────────────┐
│  Host: /Users/malone/Projects/          │
│                                         │
│  hermes-nulab/          hermes-webui/   │
│  ├── run_agent.py       ├── server.py   │
│  ├── tools/             ├── api/        │
│  ├── .hermes-data/      ├── static/     │
│  │   ├── config.yaml    └── Dockerfile  │
│  │   ├── auth.json                     │
│  │   └── sessions/                     │
│  └── docker-compose.override.yml       │
└──────────────┬──────────────────────────┘
               │ Docker
               ▼
┌──────────────────────────────────────────┐
│  Container: hermes-nulab (gateway)       │
│  - HERMES_HOME=/opt/data                 │
│  - Mount: .hermes-data → /opt/data       │
│  - Port: 127.0.0.1:18642                 │
├──────────────────────────────────────────┤
│  Container: hermes-nulab-webui           │
│  - HERMES_HOME=/opt/data                 │
│  - Mount: .hermes-data → /opt/data       │  ← shared state
│  - Mount: . (repo) → /opt/hermes-agent-src│  ← agent source (SEPARATE path!)
│  - Port: 127.0.0.1:8787                  │
│  - Startup: pip install /opt/hermes-agent-src → venv site-packages │
│  - Then: python server.py                │
└──────────────────────────────────────────┘
```

## One-liner repair if the webui breaks

```bash
# 1. Clean stale build artifacts
sudo rm -rf ./.hermes-data/hermes-agent
rm -rf build/ hermes_agent.egg-info/

# 2. Recreate the webui container
docker compose stop webui && docker compose rm -f webui && docker compose up -d webui

# 3. Wait ~30s for init, then test
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8787/
```
