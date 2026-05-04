#!/bin/bash
# Volume permission fix for multi-container access.
# Runs as root before the original entrypoint drops privileges with gosu.
# The original entrypoint does chmod 640 config.yaml, so we also fix in the
# gateway CMD (compose command) which runs as hermes user AFTER gosu.
chmod 755 /opt/data 2>/dev/null || true
exec /opt/hermes/docker/entrypoint.sh "$@"
