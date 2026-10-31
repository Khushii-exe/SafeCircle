#!/usr/bin/env bash
# Build OSRM routing data with the FOOT profile (walking routes) from the cropped extract. Needs Docker.
# Memory use depends on the extract size: run this on your laptop, check it completes, then copy data/osm/*.osrm* to the server.
set -euo pipefail
IMG=ghcr.io/project-osrm/osrm-backend
run() { docker run --rm -t -v "$PWD/data/osm:/data" "$IMG" "$@"; }
run osrm-extract -p /opt/foot.lua /data/delhi-haryana.osm.pbf
run osrm-partition /data/delhi-haryana.osrm
run osrm-customize /data/delhi-haryana.osrm
echo "Done. Start the routing server with: docker compose -f docker-compose.yml -f docker-compose.osrm.yml up"
