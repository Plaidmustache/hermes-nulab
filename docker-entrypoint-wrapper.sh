#!/bin/bash
echo "[entrypoint-wrapper] Running as: $(id)"
echo "[entrypoint-wrapper] /opt/data permissions before chmod: $(stat -c '%a %U(%u)/%G(%g)' /opt/data/ 2>/dev/null || echo 'does not exist')"
chmod 755 /opt/data || echo "[entrypoint-wrapper] WARNING: chmod 755 /opt/data failed"
chmod 644 /opt/data/config.yaml 2>/dev/null || true
echo "[entrypoint-wrapper] /opt/data permissions after chmod: $(stat -c '%a %U(%u)/%G(%g)' /opt/data/)"
echo "[entrypoint-wrapper] /opt/data/config.yaml permissions: $(stat -c '%a %U(%u)/%G(%g)' /opt/data/config.yaml 2>/dev/null || echo 'no config.yaml')"
exec /opt/hermes/docker/entrypoint.sh "$@"
