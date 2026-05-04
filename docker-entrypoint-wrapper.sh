#!/bin/bash
# Wrapper entrypoint — runs chmod as root before handing off to original entrypoint.
# Fixes volume permissions for webui container access on Coolify.
chmod 755 /opt/data 2>/dev/null || true
exec /opt/hermes/docker/entrypoint.sh "$@"
