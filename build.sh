#!/usr/bin/env bash
# osmlogo build: party.json + nouns.yaml -> baked parquet + web assets.
# Usage: ./build.sh          (uses party.json in this directory)
# Requires: cosmo (or set COSMO_BIN), duckdb, python3, curl.
set -euo pipefail
cd "$(dirname "$0")"

COSMO_BIN="${COSMO_BIN:-cosmo}"
command -v "$COSMO_BIN" >/dev/null || { echo "cosmo not found — install it or set COSMO_BIN"; exit 1; }
command -v duckdb >/dev/null || { echo "duckdb not found"; exit 1; }

party() { python3 -c "import json;v=json.load(open('party.json')).get('$1','');print(v if isinstance(v,str) else __import__('json').dumps(v))"; }
NAME=$(party name)
URL=$(party extract_url)
ADMIN_LEVEL=$(party admin_level)

echo "== osmlogo build: $NAME (admin_level=$ADMIN_LEVEL) =="

mkdir -p data out baked web/lang party
PBF="data/$(basename "$URL")"
if [ ! -f "$PBF" ]; then
  echo "-- downloading $URL"
  curl -L --fail -o "$PBF" "$URL"
else
  echo "-- using cached $PBF (delete to re-download)"
fi

# Party pad: bake a link once; the first person to open it creates the pad.
# Kept across rebuilds — delete web/party.json to get a fresh pad.
if [ ! -f web/party.json ]; then
  python3 - "$NAME" <<'PYEOF'
import json, re, secrets, sys
slug = re.sub(r"[^a-z0-9]+", "-", sys.argv[1].lower()).strip("-")
url = f"https://pad.riseup.net/p/partykit-{slug}-{secrets.token_hex(3)}"
json.dump({"pad_url": url}, open("web/party.json", "w"), indent=2)
print(f"-- party pad: {url}")
PYEOF
else
  echo "-- party pad: $(python3 -c "import json;print(json.load(open('web/party.json'))['pad_url'])") (kept)"
fi

# Inject the region's admin_level into the boundaries filter.
sed "s/admin_level=[0-9]*/admin_level=$ADMIN_LEVEL/" nouns.yaml > data/filters.yaml

echo "-- extracting noun tables (cosmo)"
"$COSMO_BIN" validate data/filters.yaml
"$COSMO_BIN" convert -i "$PBF" -o out -f data/filters.yaml --format geoparquet

echo "-- baking (place assignment + proximity counts)"
duckdb -c ".read queries/bake.sql"

echo "== done. python3 serve.py and share the URL with the room =="
