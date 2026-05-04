# Hermes Nulab Local Instance

This checkout is intentionally isolated from the existing `paperclip-hermes`
deployment.

Local isolation choices:

- Docker Compose project: `hermes-nulab`
- Gateway container: `hermes-nulab`
- Dashboard container: `hermes-nulab-dashboard`
- Hermes state directory: `./.hermes-data`
- Local API server: `127.0.0.1:18642`
- Local dashboard: `127.0.0.1:19119`
- API model name: `hermes-nulab`

The upstream compose file mounts `~/.hermes`; `docker-compose.override.yml`
replaces that with `./.hermes-data` so local setup, config, sessions, memories,
skills, and logs stay inside this project.

The override also uses Docker bridge networking with localhost-bound ports
instead of upstream `network_mode: host`, which avoids Docker Desktop host
networking surprises on macOS.

The dashboard runs with Hermes' `--insecure` flag inside Docker only so it can
bind to `0.0.0.0` in the container. Docker publishes it to localhost only:
`127.0.0.1:19119`.

Embedded chat is enabled with `--tui`, which exposes `/chat` in the dashboard
and runs the same Hermes TUI you get from the terminal CLI.

Provider keys:

- `DEEPSEEK_API_KEY` is passed through from the host shell that runs
  `docker compose`.
- `DEEPSEEK_BASE_URL` defaults to `https://api.deepseek.com`.
- The DeepSeek API key is not stored in this repo's `.env`.

Run locally:

```sh
docker compose up -d --build
```

Open the dashboard:

```text
http://127.0.0.1:19119
```

Check the API health:

```sh
curl -H "Authorization: Bearer dev-only-hermes-nulab" \
  http://127.0.0.1:18642/health
```

Stop it:

```sh
docker compose down
```

Remove local Hermes state for this instance only:

```sh
rm -rf .hermes-data
```

Do not attach this instance to `paperclip-agent-net` or give it the Docker
network alias `hermes` unless you intentionally want PaperClip to route to it.
