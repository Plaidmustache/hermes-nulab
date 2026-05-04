#!/bin/bash
chmod 755 /opt/data || true
chmod 644 /opt/data/config.yaml || true
exec /opt/hermes/docker/entrypoint.sh "$@"
# After original entrypoint finishes (should never reach here since entrypoint execs hermes)
stat -c '%a' /opt/data/
