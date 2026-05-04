#!/bin/bash
chmod 755 /opt/data 2>/dev/null || true
chmod 644 /opt/data/config.yaml 2>/dev/null || true
exec /opt/hermes/docker/entrypoint.sh "$@"
