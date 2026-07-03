# osmlogo

Experiment: a LOGO-like constrained query vocabulary over OSM, materialized
locally. Nouns are curated tag bundles compiled to [cosmo](../cosmo) tables;
predicates (WITHOUT attr / CONTAINING NO noun / OLDER THAN duration / IN place)
run as DuckDB SQL over the resulting GeoParquet. No live services.

## Pipeline

```
data/utah-latest.osm.pbf          # Geofabrik public extract (has timestamps, no user ids)
  └─ cosmo convert -i data/utah-latest.osm.pbf -o out -f nouns.yaml --format geoparquet
       └─ out/*.parquet           # one table per noun (~2 min for Utah)
            └─ duckdb -c ".read queries/demo.sql"
```

- `nouns.yaml` — the noun dictionary (14 nouns). Tag bundles are editorial
  decisions and the core curated artifact.
- `queries/demo.sql` — the seven demo queries.
- `boundaries` table (admin_level=8 relations) provides the `IN <place>` dropdown.

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

## Known v0 warts

- `ST_DWithin` uses degrees (0.0015 ≈ 150 m at this latitude).
- `timestamp` is a varchar ISO string; string comparison works, dates hardcoded.
- Public Geofabrik extract lacks user/changeset metadata (GDPR); timestamps OK.
- Spatial anti-joins are computed at query time; fine at Utah scale, would be
  precomputed as contains-count columns at extract time for bigger regions.
