#!/bin/bash
echo "[entrypoint-wrapper] fixing volume permissions..."
chmod 755 /opt/data || echo "[entrypoint-wrapper] WARNING: chmod /opt/data failed"
chmod 644 /opt/data/config.yaml || echo "[entrypoint-wrapper] WARNING: chmod config.yaml failed"
exec /opt/hermes/docker/entrypoint.sh "$@"
