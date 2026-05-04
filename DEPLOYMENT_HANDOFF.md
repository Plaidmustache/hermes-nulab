# Hermes-Nulab Deployment Handoff

Quick-start reference. For full operational detail, see the **Obsidian runbooks**:

- **`02-VPS Runbooks/Hermes-Nulab Coolify Deployment.md`** — full deployment guide, all 19 sections
- **`02-VPS Runbooks/Hindsight Memory on Coolify.md`** — Hindsight setup companion

## Quick Deploy

1. Push to `main` → GitHub webhook → Coolify auto-deploys
2. Env vars in Coolify: `DEEPSEEK_API_KEY`, `OPENPASS_PASSPHRASE`, `OPENPASS_MCP_TOKEN`, `GATEWAY_ALLOW_ALL_USERS`
3. Verify: `curl https://hermes.nulab.cc/health` → 200

## Compose Files

| File | Purpose |
|---|---|
| `docker-compose.yml` | Base (upstream) |
| `docker-compose.override.yml` | Local dev (auto-merged) |
| `docker-compose.coolify.yml` | Coolify VPS deployment |

## Post-Deploy

One-time: `sudo chmod 755 /var/lib/docker/volumes/<uuid>_hermes-data/_data` on the VPS host to fix volume permissions for the WebUI.
