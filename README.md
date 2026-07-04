# OpenStreetMap Mapping Party Kit!

An offline-first mapping party kit for local OpenStreetMap groups. 


Run it on one laptop, share the URL with the group, and fix the map together!

## Make your own

1. Edit `region.json` — the area, boundary admin_level, language, map
   center. That's the "fill in the area" part. Two ways to give the area:
   - `area`: a GeoJSON geometry or `[w,s,e,n]` bbox — fetched minutely-fresh
     from [SliceOSM](https://slice.openstreetmap.us), sized to your party
     instead of your state. **Use the party city's polygon** (e.g. Nominatim
     with `polygon_geojson=1`), not a bbox: SliceOSM only includes boundary
     ways that intersect the area, so a bbox smaller than the city clips its
     boundary and breaks place assignment. The city's own polygon always
     survives intact (its boundary ways *are* the area edge).
   - `extract_url`: a Geofabrik extract URL (used when `area` is absent) —
     for whole-state parties or when SliceOSM is down.
2. Optionally edit `web/lang/<lang>.json` — the language dialect: noun labels,
   UI strings, example sentences. Add a new file for a new language and point
   `region.json` at it. Tag bundles live in `nouns.yaml` and often deserve
   regional tuning too.
3. `./build.sh` (needs cosmo or `COSMO_BIN`, duckdb, curl, python3)
4. Host the directory on any static server with Range support and open `/web/`.

## Map together (same room)

```
python3 serve.py        # prints http://<your-lan-ip>:8765/web/
```

Everyone on the same network opens that URL — each browser runs its own
DuckDB-WASM against the same baked data; there is no shared server state.
The sentence lives in the URL hash, so any query is a shareable link: the
**share** button shows a QR + copy-link for the room, and pasting a shared
link into an already-open tab takes effect immediately. (Clients still need
internet for map tiles and the CDN-hosted engine.)

## Pipeline

```
region.json ─┐
nouns.yaml ──┴─ build.sh
                ├─ SliceOSM (area) or Geofabrik  → data/*.osm.pbf   (cached; delete to re-fetch)
                ├─ cosmo convert (filters.yaml)  → out/*.parquet   (~2 min for Utah)
                └─ duckdb queries/bake.sql       → baked/*.parquet, web/boundaries.geojson, web/places.json
web/index.html + web/lang/<lang>.json  →  the sentence-builder app
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
baked parquet. DuckDB-WASM (CDN) + MapLibre GL JS, no server-side anything.

```
python3 -m http.server 8017    # from the osmlogo dir
open http://localhost:8017/web/
```

- Live counts in the + add picker (the answer arrives before the question)
- Guardrail banner when >95% of features miss an attribute (campaign, not gap)
- Dots capped at 2000; popups link to osm.org and "fix in iD"
- Query state serializes to the URL hash — shareable sentences
- Verified end-to-end with headless Chrome: SLC museums = 19, parks = 1740,
  matching the DuckDB baselines exactly
- python http.server lacks Range support so duckdb-wasm falls back to full
  file reads; any real static host (nginx, GitHub Pages, Caddy) does partial
  reads and only touches the row groups it needs

## Known v0 warts

- `ST_DWithin` uses degrees (0.0015 ≈ 150 m at this latitude).
- `timestamp` is a varchar ISO string; string comparison works, dates hardcoded.
- Public Geofabrik extract lacks user/changeset metadata (GDPR); timestamps OK.
- Spatial anti-joins are computed at query time; fine at Utah scale, would be
  precomputed as contains-count columns at extract time for bigger regions.
