# Hindsight Memory Setup for Hermes

## Architecture

```
hermes gateway ──HTTP──▶ Hindsight container (port 8888)
                              │
                              ├── PostgreSQL (embedded, auto-managed)
                              ├── DeepSeek LLM (entity extraction, synthesis)
                              ├── Embedding model (bge-small-en-v1.5, auto-downloaded)
                              └── Reranker (ms-marco-MiniLM-L-6-v2, auto-downloaded)
```

Hindsight runs as a **separate Docker container** using the pre-built image `ghcr.io/vectorize-io/hindsight:latest`. Hermes connects to it in `local_external` mode. This avoids baking the heavy ML stack (PyTorch, CUDA, transformers — ~2GB) into the gateway image.

## Why This Approach

| Attempt | What | Why it failed |
|---------|------|---------------|
| local_embedded | Install `hindsight-all` inside gateway container | Torch + CUDA = 2GB, Docker build timed out, ran out of disk space |
| local_external | Separate container with pre-built image | ✅ Works, no PyTorch in gateway, just `hindsight-client` (~100KB) |

## Step 1: Add Hindsight container to docker-compose

```yaml
# docker-compose.override.yml
services:
  hindsight:
    image: ghcr.io/vectorize-io/hindsight:latest
    container_name: hermes-nulab-hindsight
    network_mode: bridge
    ports:
      - "127.0.0.1:8888:8888"   # API
      - "127.0.0.1:9999:9999"   # Web UI (optional monitoring)
    volumes:
      - ./.hermes-data/hindsight-data:/home/hindsight/.pg0
    environment:
      - HINDSIGHT_API_LLM_PROVIDER=deepseek
      - HINDSIGHT_API_LLM_API_KEY=${DEEPSEEK_API_KEY}
      - HINDSIGHT_API_LLM_MODEL=deepseek-chat
    restart: unless-stopped
```

**Key points:**
- `HINDSIGHT_API_LLM_PROVIDER=deepseek` — uses LiteLLM under the hood, which supports DeepSeek natively
- `HINDSIGHT_API_LLM_MODEL=deepseek-chat` — the DeepSeek model for memory extraction/synthesis
- Volume mounts PostgreSQL data so memories survive container rebuilds
- `network_mode: bridge` — same as gateway, reachable via `host.docker.internal`

## Step 2: Configure Hermes memory provider

### config.yaml
```yaml
memory:
  memory_enabled: true
  provider: hindsight
```

### hindsight/config.json
```json
{
  "mode": "local_external",
  "api_url": "http://host.docker.internal:8888",
  "bank_id": "hermes-nulab",
  "auto_recall": true,
  "auto_retain": true,
  "recall_budget": "mid",
  "memory_mode": "hybrid"
}
```

**Key points:**
- `mode: local_external` — connects to the separate Hindsight container, NOT embedded mode
- `api_url` uses `host.docker.internal` — the gateway reaches the Hindsight container through the host's port publish
- `memory_mode: hybrid` — both auto-injection into context AND tools available to the agent (`hindsight_retain`, `hindsight_recall`, `hindsight_reflect`)

## Step 3: Install Python client

The `hindsight-client` package must be installed in the gateway's venv:

```bash
docker exec hermes-nulab sh -c 'cd /opt/hermes && . .venv/bin/activate && uv pip install "hindsight-client>=0.4.22"'
```

Then restart the gateway **without removing the container** (or the install is lost):

```bash
docker compose restart gateway    # preserves writable layer
# NOT: docker compose rm gateway  # would lose the install
```

**Critical:** The gateway container's venv is baked into the image. Any `uv pip install` is lost on `docker compose rm`. Use `docker compose restart` to keep packages. For Coolify/VPS, either:
- Add `hindsight-client` to the gateway Dockerfile as a build step, OR
- Mount the venv as a volume so packages persist

## Step 4: Pass API keys to gateway

The gateway container needs `DEEPSEEK_API_KEY` (for the agent) AND Hindsight needs a separate env var:

```yaml
# In gateway service:
environment:
  - DEEPSEEK_API_KEY=${DEEPSEEK_API_KEY:-}
  - HINDSIGHT_LLM_API_KEY=${DEEPSEEK_API_KEY:-}       # Plugin reads this
  - HINDSIGHT_API_LLM_API_KEY=${DEEPSEEK_API_KEY:-}    # Daemon reads this
```

**Both env vars are needed** — the plugin and the daemon use different names for the same thing:
- `HINDSIGHT_LLM_API_KEY` — the Hermes Hindsight plugin reads this
- `HINDSIGHT_API_LLM_API_KEY` — the Hindsight daemon/server reads this

If only one is set, the daemon fails with: `ValueError: LLM API key is required. Set HINDSIGHT_API_LLM_API_KEY environment variable.`

## Step 5: Start and verify

```bash
# Pull and start Hindsight
docker compose up -d hindsight

# Wait for health check (first boot downloads embedding models ~30s)
curl http://127.0.0.1:8888/health
# Expected: {"status":"healthy","database":"connected"}

# Restart gateway to pick up config
docker compose restart gateway

# Test via webui: ask the agent to use hindsight_retain
# "Store this in Hindsight: <fact>"
# "Recall from Hindsight: <query>"
```

## First-Boot Notes

On first start, Hindsight downloads:
- Embedding model: `BAAI/bge-small-en-v1.5` (~130MB)
- Reranker: `cross-encoder/ms-marco-MiniLM-L-6-v2` (~90MB)

These are cached in the Docker image after first pull, so subsequent starts are fast (~5 seconds).

## Disk Space Warning

The Hindsight Docker image is ~1GB (includes baked-in Python, ML libraries). The embedding models add ~220MB on first run. Make sure you have at least 3GB free before starting.

We ran out of space during setup — had to remove ~7.6GB of unused Docker images (`zeroclaw`, `openviking`, `embedding`, `context7`, `omnisearch`, `coolify`, `signoz`) to make room.

## Troubleshooting

### Daemon fails to start: "LLM API key is required"
The `HINDSIGHT_API_LLM_API_KEY` env var is not set on the gateway container. Check:
```bash
docker exec hermes-nulab sh -c 'echo $HINDSIGHT_API_LLM_API_KEY | head -c 20'
```

### hindsight_retain tool not available
The `hindsight-client` package isn't installed. Install it:
```bash
docker exec hermes-nulab sh -c 'cd /opt/hermes && . .venv/bin/activate && uv pip install "hindsight-client>=0.4.22"'
docker compose restart gateway
```

### Memories don't persist across container recreates
The PostgreSQL data is mounted at `.hermes-data/hindsight-data`. Verify:
```bash
ls -la .hermes-data/hindsight-data/
```

### Gateway can't reach Hindsight
The `host.docker.internal` hostname might not resolve. Test from the gateway:
```bash
docker exec hermes-nulab wget -qO- http://host.docker.internal:8888/health
```
If it fails, try using the container name: `http://hermes-nulab-hindsight:8888` (requires both containers on the same Docker network).
