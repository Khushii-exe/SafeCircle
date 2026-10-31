#!/usr/bin/env bash
# Download OpenStreetMap data for Delhi + Haryana and crop it. Needs: curl, osmium-tool (apt install osmium-tool).
# Source: Geofabrik "India, Northern Zone" extract. Check the cropped file really contains both Delhi and Haryana
# (open it in QGIS or run `osmium fileinfo -e`), because Geofabrik zone borders can change.
# Data is (c) OpenStreetMap contributors, ODbL: keep the attribution in the app and console.
set -euo pipefail
mkdir -p data/osm && cd data/osm
curl -L -o northern-zone.osm.pbf https://download.geofabrik.de/asia/india/northern-zone-latest.osm.pbf
# bbox order is west,south,east,north and matches app/region.py
osmium extract --bbox 74.40,27.60,77.65,30.95 --strategy complete_ways northern-zone.osm.pbf -o delhi-haryana.osm.pbf --overwrite
osmium fileinfo -e delhi-haryana.osm.pbf
