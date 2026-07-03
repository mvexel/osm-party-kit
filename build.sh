#!/usr/bin/env bash
# osmlogo build: region.json + nouns.yaml -> baked parquet + web assets.
# Usage: ./build.sh          (uses region.json in this directory)
# Requires: cosmo (or set COSMO_BIN), duckdb, python3, curl.
set -euo pipefail
cd "$(dirname "$0")"

COSMO_BIN="${COSMO_BIN:-cosmo}"
command -v "$COSMO_BIN" >/dev/null || { echo "cosmo not found — install it or set COSMO_BIN"; exit 1; }
command -v duckdb >/dev/null || { echo "duckdb not found"; exit 1; }

region() { python3 -c "import json;print(json.load(open('region.json'))['$1'])"; }
NAME=$(region name)
URL=$(region extract_url)
ADMIN_LEVEL=$(region admin_level)
PBF="data/$(basename "$URL")"

echo "== osmlogo build: $NAME (admin_level=$ADMIN_LEVEL) =="

mkdir -p data out baked web/lang
if [ ! -f "$PBF" ]; then
  echo "-- downloading $URL"
  curl -L --fail -o "$PBF" "$URL"
else
  echo "-- using cached $PBF"
fi

# Inject the region's admin_level into the boundaries filter.
sed "s/admin_level=[0-9]*/admin_level=$ADMIN_LEVEL/" nouns.yaml > data/filters.yaml

echo "-- extracting noun tables (cosmo)"
"$COSMO_BIN" validate data/filters.yaml
"$COSMO_BIN" convert -i "$PBF" -o out -f data/filters.yaml --format geoparquet

echo "-- baking (place assignment + proximity counts)"
duckdb -c ".read queries/bake.sql"

echo "== done. serve the project dir and open /web/ =="
echo "   e.g.: caddy file-server --listen :8017   (or any static host with Range support)"
