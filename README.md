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

Build the data first, then package and serve the built Kit:

```
./build.sh
docker build -t osmlogo-party .
docker run --rm -p 8765:8765 -v "$PWD/party:/app/party" osmlogo-party
```

The bind mount preserves `party/scribbles.jsonl` outside the container.

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
- `queries/demo.sql`, `queries/candidates.sql` — CLI query sets from the
  design sessions.

## Findings from run 2026-07-03

- MUSEUMS WITHOUT OPENING_HOURS IN SLC: 19 of ~30
- PARKS CONTAINING NO BENCHES: 1740 / 2033 named parks — but top results are
  OHV areas and trail systems tagged leisure=park → the PARK noun bundle needs
  editorial tightening. The noun problem, observed live.
- PLAYGROUNDS w/o toilet within ~150 m: 2716 / 3251
- SHOPS OLDER THAN 2 YEARS IN PARK CITY: 36 / 120 (oldest untouched since 2012)
- CROSSINGS WITHOUT LIT IN SLC: 12,493 — i.e. **zero** crossings have lit=*.
  100% missing means the query surfaces an unmapped attribute, not a story;
  candidate for a "not enough signal" guardrail in the UI.
- BUILDINGS WITHOUT ADDRESS IN SLC: 27,041 / 77,032 (35%)
- RESTAURANTS EDITED SINCE 1 MONTH: 212 statewide (the positive story)

## Round 2 candidate queries (queries/candidates.sql, run 2026-07-03)

- BUS_STOPS WITHOUT SHELTER: 4800 / 6554 (bench: 5016, unnamed: 240)
- RESTAURANTS WITHOUT CUISINE: 1139 / 5933
- RESTAURANTS WITH WEBSITE BUT WITHOUT OPENING_HOURS: 762 (great armchair list)
- SHOPS WITHOUT NAME: 1067 / 9798
- SHOPS NEVER EDITED (version=1) AND OLDER THAN 3 YEARS: 1396 — "mapped once
  and forgotten," incl. supermarkets untouched since 2009
- CROSSINGS WITHOUT TACTILE_PAVING: 105k / 113k — near-total absence, campaign
  not story (same guardrail case as lit)
- SCHOOLS WITH NO CROSSING WITHIN ~150M: 161 / 1286 — safe-routes story
- DUPLICATE-NAME RESTAURANTS within 100m: 0 (clean, or the check is too strict)

Note: found+fixed a cosmo bug en route — meta:* columns declared type:integer
were silently written as NULL (string value dropped by typed sink).

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
