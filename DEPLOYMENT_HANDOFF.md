# Hermes-Nulab Deployment Handoff

Quick-start reference. For full operational detail, see the **Obsidian runbooks**:

- **`02-VPS Runbooks/Hermes-Nulab Coolify Deployment.md`** — full deployment guide, all 19 sections
- **`02-VPS Runbooks/Hindsight Memory on Coolify.md`** — Hindsight setup companion

## Quick Deploy

1. Push to `main` → GitHub webhook → Coolify auto-deploys
2. Env vars in Coolify: `DEEPSEEK_API_KEY`, `OPENPASS_PASSPHRASE`, `OPENPASS_MCP_TOKEN`, `GATEWAY_ALLOW_ALL_USERS`, `ZAI_API_KEY`
3. Verify: `curl https://hermes.nulab.cc/health` → 200

## Compose Files

| File | Purpose |
|---|---|
| `docker-compose.yml` | Base (upstream) |
| `docker-compose.override.yml` | Local dev (auto-merged) |
| `docker-compose.coolify.yml` | Coolify VPS deployment |

## Key Architecture Notes

- **Hindsight config:** Standard path `~/.hermes/hindsight/config.json` resolves to `/opt/data/hindsight/config.json` because `HERMES_HOME=/opt/data`. Mode: `local_external`, URL: `http://hindsight:8888`, memory: `hybrid`.
- **OpenPass credential retrieval:** Cross-container password needs (Himalaya, etc.) use a helper script that curls the OpenPass MCP HTTP endpoint. Not the CLI — it can't reach across containers. Containers stay decoupled: no shared volumes or binaries.
- **Memory is unified:** `memory.provider: hindsight` means the built-in `memory()` tool is backed by Hindsight. One system, not two.

## Post-Deploy

One-time: `sudo chmod 755 /var/lib/docker/volumes/<uuid>_hermes-data/_data` on the VPS host to fix volume permissions for the WebUI.
