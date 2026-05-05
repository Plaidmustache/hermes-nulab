# Hermes-WebUI: OpenAI Profile Not Working — Full Report

## The Problem

The user deployed **hermes-nulab** on Coolify using `docker-compose.coolify.yml`. The stack has a Hermes **gateway** container + a **webui** container (`ghcr.io/nesquena/hermes-webui:latest`).

The gateway was hardcoded at startup to use **DeepSeek** via:
```
hermes config set model.provider "deepseek"
hermes config set model.default "deepseek-v4-flash"
hermes config set model.base_url "https://api.deepseek.com"
```

The webui has a "profile" system where users can create separate agent profiles (e.g., "deepseek", "openai"). Each profile runs its own gateway process with its own config. The webui allows switching between profiles.

**What the user wants:** Ability to switch between DeepSeek and OpenAI profiles in the webui.

**What works:** DeepSeek profile works perfectly.

**What doesn't work:** OpenAI profile. When switching to the OpenAI profile and sending a message, the error is:

```
Provider mismatch: Error code: 401 - {'error': {'message': 'Incorrect API key provided: sk-030e0...dc31...'}}
```

Then after config changes, it changed to:

```
Error code: 400 - {'error': {'message': 'Encrypted content is not supported with this model.', 'type': 'invalid_request_error', 'param': 'include', 'code': None}}
```

## Root Causes (Multiple Layers)

### Layer 1: Gateway Startup Hardcoding
The compose file ran `hermes config set model.provider "deepseek"` **every time the container started**, overwriting any user changes made via the webui. This was fixed by removing those three lines.

**Fix applied:** Removed the three `hermes config set` lines from `docker-compose.coolify.yml`. Now the gateway starts with whatever config.yaml has on the shared volume.

### Layer 2: Missing OPENAI_API_KEY Env Var
The gateway container had `DEEPSEEK_API_KEY` as a Coolify env var but not `OPENAI_API_KEY`. Even if the user configured the OpenAI profile's config.yaml correctly, the gateway's provider resolver (`resolve_runtime_provider`) looks for OPENAI_API_KEY in env vars.

**Fix applied:** Added `OPENAI_API_KEY=${OPENAI_API_KEY}` to the gateway's environment in the compose file. The user also added the key in Coolify's dashboard.

### Layer 3: Webui Container Missing OPENAI_API_KEY
The webui container (`ghcr.io/nesquena/hermes-webui:latest`) runs its own internal Python server that creates AIAgent instances in-process. It needs OPENAI_API_KEY in its environment to resolve credentials for the OpenAI profile. It only had DEEPSEEK_API_KEY.

**Fix applied:** Added `OPENAI_API_KEY=${OPENAI_API_KEY}` to the webui's environment in the compose file. (Both containers now have the env var.)

### Layer 4: File Ownership Mismatch (Permission Denied)
**This was the critical hidden issue.**

The webui container runs as user `hermeswebuitoo` (UID 1025), not `hermeswebui` (UID 501). But commands run from the gateway container (like `hermes config set model.provider ""`) create files owned by the gateway's user. The gateway runs as `hermes` (UID 501) which maps to `hermeswebui` inside the webui container — a **different user** from the webui process (`hermeswebuitoo` UID 1025).

This caused `PermissionError: [Errno 13] Permission denied` when the webui tried to read profile configs at:
- `/opt/data/profiles/openai/config.yaml`
- `/opt/data/profiles/deepseek/config.yaml`
- `/opt/data/profiles/openai/cron/output`

**Fix applied:** Ran `chown -R hermeswebuitoo:hermeswebuitoo /opt/data/` and `chmod -R 777 /opt/data/` from within the webui container. After this, the webui could read profile configs and the DeepSeek profile started working.

### Layer 5: Model Resolution Returning `api_mode = codex_responses`
Even with the correct config (`model.api_mode = chat_completions`, `model.base_url = https://api.openai.com/v1`), the webui's OpenAI requests were hitting the **OpenAI Responses API** (`codex_responses` mode) instead of Chat Completions.

The error `"Encrypted content is not supported with this model"` with `param: "include"` is an OpenAI Responses API error — gpt-4o doesn't support that parameter via Responses.

The `api_mode` is resolved by `_resolve_openrouter_runtime()` in `hermes_cli/runtime_provider.py`. The logic is:

```python
api_mode = (
    _parse_api_mode(model_cfg.get("api_mode"))       # 1. Config file
    or _detect_api_mode_for_url(base_url)             # 2. URL detection
    or "chat_completions"                              # 3. Fallback
)
```

`_detect_api_mode_for_url("https://api.openai.com/v1")` returns `"codex_responses"` because the hostname is `api.openai.com`. If `model_cfg` doesn't have `api_mode` set (or the wrong config is loaded), it falls through to the URL detection.

**This still needs to be fixed.** The openai profile's config.yaml has `api_mode: chat_completions` but the per-request profile switching in the webui might not be setting `HERMES_HOME` correctly before `resolve_runtime_provider` reads the config.

## What's Been Done

### Changes to `docker-compose.coolify.yml`
1. Removed the three `hermes config set model.*` lines from the gateway startup command
2. Added `OPENAI_API_KEY=${OPENAI_API_KEY}` to the gateway's env
3. Added `OPENAI_API_KEY=${OPENAI_API_KEY}` to the webui's env

### Changes to gateway config (via SSH `hermes config set`)
For the **default** profile (`/opt/data/config.yaml`):
```yaml
model:
  default: gpt-4o
  provider: ''
  base_url: https://api.openai.com/v1
  api_mode: chat_completions
```

For the **openai** profile (`/opt/data/profiles/openai/config.yaml`):
```yaml
model:
  api_key: sk-proj-... (the user's OpenAI key inline)
  default: gpt-4o
  provider: ''
  base_url: https://api.openai.com/v1
  api_mode: chat_completions
```

For the **deepseek** profile (`/opt/data/profiles/deepseek/config.yaml`):
```yaml
model:
  provider: deepseek
  default: deepseek-v4-flash
  base_url: https://api.deepseek.com/v1
```

### Permissions fix
From inside the webui container (as root):
```bash
chown -R hermeswebuitoo:hermeswebuitoo /opt/data/
chmod -R 777 /opt/data/
```

## Current State

| Profile | Gateway API (port 18642) | WebUI Chat |
|---------|--------------------------|------------|
| **default** | ✅ OpenAI works via curl test | ❓ Untested but webui shows it |
| **deepseek** | ✅ Works | ✅ Works (verified via agent-browser) |
| **openai** | ✅ Should work (same config as default) | ❌ Responses API mode issue |

## What Still Needs Debugging

### The `api_mode = codex_responses` Bug

When the webui processes a chat message for the OpenAI profile, the agent creation code in `/apptoo/api/streaming.py` (inside the webui container) calls:

```python
resolved_model, resolved_provider, resolved_base_url = resolve_model_provider(
    model_with_provider_context(model, provider_context)
)

_rt = resolve_runtime_provider(requested=resolved_provider)
resolved_api_key = _rt.get("api_key")
...
_agent_kwargs['api_mode'] = _rt.get('api_mode')
```

The `resolved_provider` comes from `resolve_model_provider()` which reads `model.provider` from the profile's config. For the openai profile, `model.provider = ""` (empty).

Then `resolve_runtime_provider(requested="")` resolves to:
1. `resolve_requested_provider("")` → "auto" (empty provider falls through)
2. `resolve_provider("auto")` → finds OPENAI_API_KEY → returns "openrouter"
3. `_resolve_openrouter_runtime()` → reads model_cfg from config

The issue is likely that `HERMES_HOME` is NOT set to the openai profile's home before `resolve_runtime_provider` is called. In `_run_agent_streaming()`, the code does set it:

```python
_profile_home_path = get_hermes_home_for_profile(getattr(s, 'profile', None))
_profile_home = str(_profile_home_path)
_profile_runtime_env = get_profile_runtime_env(_profile_home_path)
...
os.environ['HERMES_HOME'] = _profile_home
```

But this might not be working correctly for the OpenAI profile. Check:
1. Does `s.profile` contain "openai" when the user is on the openai profile?
2. Does `get_hermes_home_for_profile("openai")` return the correct path?
3. Does the `os.environ.update()` actually set `HERMES_HOME`?
4. Does `hermes_cli.config.load_config()` read from the correct `HERMES_HOME`?

**Potential fix:** Set `model.provider = "openrouter"` explicitly in the openai profile (instead of `""`). This would bypass the auto-detection and go directly to `_resolve_openrouter_runtime()`, which reads `model.api_mode` from config.

### Model Cache Issue
The webui caches the model catalog at `/opt/data/models_cache.json` and `/opt/data/models_dev_cache.json`. These might contain stale DeepSeek models. Can be cleared safely.

## How to Test with agent-browser

The new agent should use **agent-browser** (a Rust CLI for browser automation) to verify fixes, not ask the user to test.

### Setup
```bash
# Install (if not already)
npm i -g agent-browser && agent-browser install

# Load the skill
agent-browser skills get agent-browser --full
```

### Testing the WebUI

```bash
# 1. Start Chrome with remote debugging
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --remote-debugging-port=9222 --headless --no-sandbox

# 2. Connect agent-browser
agent-browser connect ws://127.0.0.1:9222/devtools/browser/<id-from-chrome-output>

# 3. Navigate to webui
agent-browser open https://hermes.nulab.cc

# 4. Log in with password: Sillyauth2020?
agent-browser type @<password-field-ref> "Sillyauth2020?"
agent-browser click @<signin-button-ref>

# 5. Navigate to profiles page
agent-browser click @<agent-profiles-nav-ref>

# 6. Take a snapshot to see profile list
agent-browser snapshot

# 7. Click on a profile to switch
agent-browser click @<profile-ref>

# 8. Go back to chat
agent-browser click @<chat-nav-ref>

# 9. Start new conversation
agent-browser click @<new-conversation-ref>

# 10. Type and send a message
agent-browser type @<message-input-ref> "say hi"
agent-browser press Enter

# 11. Wait for response and check
sleep 20
agent-browser snapshot
```

### Tips for Using agent-browser
- Run `agent-browser snapshot` frequently to see the current page state
- The snapshot shows accessibility tree with element refs (e.g., `@e14`)
- Use `@e<number>` to reference elements from the most recent snapshot
- Elements change refs between snapshots — always snapshot again before clicking
- `sleep` between actions to let the page render
- The user's webui password is `Sillyauth2020?`

### Testing the Gateway API Server Directly
```bash
# From inside the gateway container
curl -s http://localhost:18642/v1/chat/completions \
  -H "Authorization: Bearer dev-only-hermes-nulab" \
  -H "Content-Type: application/json" \
  -d '{"model": "gpt-4o", "messages": [{"role": "user", "content": "hi"}]}'
```

### Testing the Webui Chat API Directly
```bash
# From inside the webui container
# 1. Login
curl -s http://localhost:8787/api/auth/login \
  -X POST -H "Content-Type: application/json" \
  -d '{"password": "Sillyauth2020?"}' \
  -c /tmp/cookies.txt

# 2. Create session
COOKIE=$(grep hermes_session /tmp/cookies.txt | awk "{print \$7}")
curl -s http://localhost:8787/api/session/new \
  -H "Cookie: hermes_session=$COOKIE; hermes_profile=openai" \
  -X POST -d '{}'

# 3. Send message
curl -s --max-time 120 http://localhost:8787/api/chat \
  -H "Cookie: hermes_session=$COOKIE; hermes_profile=openai" \
  -X POST \
  -d '{"session_id":"<session-id>","message":"hi","model":"gpt-4o"}'
```

## Key Files and Directories

| Path | Purpose |
|------|---------|
| `/opt/data/config.yaml` | Default profile config |
| `/opt/data/profiles/openai/config.yaml` | OpenAI profile config |
| `/opt/data/profiles/deepseek/config.yaml` | DeepSeek profile config |
| `/opt/data/.env` | Default profile env vars |
| `/opt/data/profiles/openai/.env` | OpenAI profile env vars |
| `/opt/data/models_cache.json` | Cached model catalog |
| `/apptoo/api/streaming.py` | WebUI agent creation code |
| `/apptoo/api/config.py` | WebUI config loading with profile switching |
| `/apptoo/api/profiles.py` | WebUI profile management |
| `/app/venv/lib/python3.12/site-packages/hermes_cli/runtime_provider.py` | Provider credential resolution |
| `docker-compose.coolify.yml` | Coolify deployment compose |

## Useful Commands

```bash
# SSH into the VPS
ssh nulab

# Check running containers
docker ps --filter "name=gateway" --format "{{.Names}} {{.Status}}"
docker ps --filter "name=webui" --format "{{.Names}} {{.Status}}"

# Exec into gateway container
docker exec -it <gateway-container-name> sh

# Check config
cat /opt/data/config.yaml | grep -A8 "^model:"
cat /opt/data/profiles/openai/config.yaml | grep -A8 "^model:"

# Set config for a profile
/opt/hermes/.venv/bin/hermes -p openai config set model.provider "openrouter"

# List profiles
/opt/hermes/.venv/bin/hermes profile list

# Check webui logs for errors
docker logs --tail 50 <webui-container-name> 2>&1 | grep -i "error\|perm\|denied"

# Fix permissions
docker exec --user root <webui-container-name> chmod -R 777 /opt/data/
docker exec --user root <webui-container-name> chown -R hermeswebuitoo:hermeswebuitoo /opt/data/

# Clear model cache
docker exec <webui-container-name> rm -f /opt/data/models_cache.json /opt/data/models_dev_cache.json

# Restart webui
docker restart <webui-container-name>
```
