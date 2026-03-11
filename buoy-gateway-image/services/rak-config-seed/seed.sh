#!/bin/sh
# Seed concentrator config into the shared volume.
# SUB_BAND env var selects which global_conf to use (default: 2).

set -e

SUB_BAND="${SUB_BAND:-2}"
echo "[rak-config-seed] Sub-band: ${SUB_BAND}"

mkdir -p /app/config

# Always seed local_conf (no-clobber)
cp -vn /seed/local_conf.json /app/config/ 2>/dev/null || true

# Seed the correct global_conf for the selected sub-band
TEMPLATE="/seed/global_conf.us915.sb${SUB_BAND}.json"
if [ -f "$TEMPLATE" ]; then
    cp -v "$TEMPLATE" /app/config/global_conf.json
    echo "[rak-config-seed] Seeded global_conf for US915 sub-band ${SUB_BAND}"
else
    echo "[rak-config-seed] ERROR: Template not found: ${TEMPLATE}"
    exit 1
fi

echo "[rak-config-seed] Done. Sleeping."
exec sleep infinity
