#!/usr/bin/env bash
# osmlogo build: region.json + nouns.yaml -> baked parquet + web assets.
# Usage: ./build.sh          (uses region.json in this directory)
# Requires: cosmo (or set COSMO_BIN), duckdb, python3, curl.
set -euo pipefail
cd "$(dirname "$0")"

COSMO_BIN="${COSMO_BIN:-cosmo}"
command -v "$COSMO_BIN" >/dev/null || { echo "cosmo not found — install it or set COSMO_BIN"; exit 1; }
command -v duckdb >/dev/null || { echo "duckdb not found"; exit 1; }

region() { python3 -c "import json;v=json.load(open('region.json')).get('$1','');print(v if isinstance(v,str) else __import__('json').dumps(v))"; }
NAME=$(region name)
URL=$(region extract_url)
AREA=$(region area)
ADMIN_LEVEL=$(region admin_level)

echo "== osmlogo build: $NAME (admin_level=$ADMIN_LEVEL) =="

mkdir -p data out baked web/lang
if [ -n "$AREA" ] && [ "$AREA" != "null" ]; then
  # SliceOSM (slice.openstreetmap.us): minutely-fresh extract of exactly the
  # party area. region.json "area" is a [w,s,e,n] bbox or a GeoJSON geometry.
  SLUG=$(python3 -c "import re,sys;print(re.sub(r'[^a-z0-9]+','-','$NAME'.lower()).strip('-'))")
  PBF="data/${SLUG}-slice.osm.pbf"
  if [ ! -f "$PBF" ]; then
    echo "-- requesting slice from slice.openstreetmap.us (delete $PBF to re-fetch fresh data)"
    python3 - "$NAME" "$PBF" <<'PYEOF'
import json, sys, time, urllib.request
API = "https://slice.openstreetmap.us"
name, pbf = sys.argv[1], sys.argv[2]
area = json.load(open("region.json"))["area"]
if isinstance(area, list):  # [w, s, e, n] bbox
    w, s, e, n = area
    area = {"type": "Polygon", "coordinates": [[[w, n], [w, s], [e, s], [e, n], [w, n]]]}
body = json.dumps({"RegionType": "geojson", "RegionData": area, "Name": name}).encode()
req = urllib.request.Request(f"{API}/api/", data=body, method="POST")
with urllib.request.urlopen(req) as r:
    assert r.status == 201, r.read().decode()
    uuid = r.read().decode().strip()
print(f"   slice {uuid}")
while True:
    with urllib.request.urlopen(f"{API}/api/{uuid}") as r:
        st = json.load(r)
    if st.get("Error"):
        sys.exit(f"slice failed: {st['Error']}")
    if st.get("Complete"):
        break
    print(f"   {st.get('NodesProg', 0)}/{st.get('NodesTotal', '?')} nodes...")
    time.sleep(2)
print(f"   downloading ({st['SizeBytes']} bytes, planet timestamp {st['Timestamp']})")
urllib.request.urlretrieve(f"{API}/files/{uuid}.osm.pbf", pbf)
PYEOF
  else
    echo "-- using cached $PBF"
  fi
else
  PBF="data/$(basename "$URL")"
  if [ ! -f "$PBF" ]; then
    echo "-- downloading $URL"
    curl -L --fail -o "$PBF" "$URL"
  else
    echo "-- using cached $PBF"
  fi
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
