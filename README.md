# Party Kit for OSM

**A collaborative map for OSM mapping parties you can run and share on your laptop**

Make your mapping party more fun and productive! Share a map from your laptop that empowers
all mappers to ask questions like "Show me parks that have no benches".
The results pop up instantly, and everyone can draw on the same shared map:
circle blocks, stamp fixed/question/problem marks, keep notes in a shared pad,
and open a printable party report at the end.

## Make your own

1. Edit `region.json`. This is where you select the Geofabrik `extract_url`,
   boundary `admin_level` for picking places, language, and map center.
   Advanced users can point `extract_url` at any compatible `.osm.pbf`.
2. Optional:
 - Set the language to one of the supported languages in `region.json`. Look for supported languages in `web/lang/`. You can copy an existing file and create your own, too.
 - Edit `nouns.yaml` to tune the themes or add new ones.
3. Build your Kit with `./build.sh` (needs cosmo or `COSMO_BIN`, duckdb, curl, python3)

## Map together (same room)

```
python3 serve.py        # prints http://<your-lan-ip>:8765/web/
```

Everyone on the same network opens that URL — each browser runs its own
DuckDB-WASM against the same baked data. `serve.py` is also the tiny shared
scribble hub: it appends posted lines/stamps to `party/scribbles.jsonl`, and
clients poll that file every few seconds.
The sentence lives in the URL hash, so any query is a shareable link: the
**share** button shows a QR + copy-link for the room, and pasting a shared
link into an already-open tab takes effect immediately. The share panel also
links to the party pad and report. Clients still need internet for map tiles,
the CDN-hosted engine, and pad.riseup.net.

## Run with Docker

No local deps needed — the image carries cosmo, duckdb, curl, and python:

```
docker compose up      # first start bakes the Kit, then serves it
```

Edit `region.json`, `up`. The repo directory is bind-mounted, so the
extract cache (`data/`), baked assets (`baked/`), and party scribbles
(`party/`) all persist across `down`/`up`. Rebake by deleting `baked/`
and restarting.

## Pipeline

```
region.json ─┐
nouns.yaml ──┴─ build.sh
                ├─ Geofabrik extract             → data/*.osm.pbf   (cached; delete to re-fetch)
                ├─ cosmo convert (filters.yaml)  → out/*.parquet   (~2 min for Utah)
                └─ duckdb queries/bake.sql       → baked/*.parquet, web/boundaries.geojson, web/places.json
web/index.html + web/report.html + web/lang/<lang>.json  →  the party app
```

- `nouns.yaml` — the noun dictionary (14 nouns). Tag bundles are editorial
  decisions and the core curated artifact.
- `docs/NOTES.md` — design-session findings behind the noun bundles, with
  the CLI query sets in `queries/`.

## Bake step (queries/bake.sql)

`out/` is raw cosmo output; `baked/` is what the browser consumes. The bake
precomputes all spatial work so the client never loads a spatial engine:

- `place` column on every noun (centroid point-in-polygon vs full-res
  admin_level=8 boundaries) → `IN <place>` is a string filter
- proximity-count matrix: parks.bench_count/toilet_count (intersects),
  playgrounds.toilets/water/benches_within_150m, schools.crossings/
  bus_stops_within_150m → `CONTAINING NO x` is `x_count = 0`
- `boundaries_display.parquet` — simplified for rendering only, never
  used for assignment

Runs in ~1.4 s for Utah. Verified: all baked counts match the live-spatial
demo query results exactly (19 / 1740 / 2716 / 161 / 36 / 27041).
~4% of shops get no place (unincorporated areas) — place=NULL means
"statewide only", surface as such in the UI.

## Web app (web/index.html)

Sentence-builder UI: "Show me [NOUN] [predicate chips] [in PLACE]" over the
baked parquet. DuckDB-WASM (CDN) + MapLibre GL JS, with `serve.py` adding
Range support and the optional LAN scribble API.

```
python3 serve.py
open http://localhost:8765/web/
```

- Live counts in the + add picker (the answer arrives before the question)
- Guardrail banner when >95% of features miss an attribute (campaign, not gap)
- Dots capped at 2000; popups link to osm.org and "fix in iD"
- Query state serializes to the URL hash — shareable sentences
- Draw mode adds shared freehand lines and emoji stamps when served by `serve.py`
- `web/report.html` renders the final scribbles and contributor counts for printing
- Verified end-to-end with headless Chrome: SLC museums = 19, parks = 1740,
  matching the DuckDB baselines exactly
- Plain static hosting still works for query/view mode, but draw tools are
  hidden because there is no `/api/scribble` endpoint.

## Known v0 warts

- `ST_DWithin` uses degrees (0.0015 ≈ 150 m at this latitude).
- `timestamp` is a varchar ISO string; string comparison works, dates hardcoded.
- Public Geofabrik extract lacks user/changeset metadata (GDPR); timestamps OK.
- Spatial anti-joins are computed at query time; fine at Utah scale, would be
  precomputed as contains-count columns at extract time for bigger regions.
