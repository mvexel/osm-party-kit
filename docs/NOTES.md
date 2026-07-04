# Design-session notes

Spike findings from the query design sessions. The CLI query sets that
produced them live in `queries/demo.sql` and `queries/candidates.sql`
(run from the repo root: `duckdb -c ".read queries/demo.sql"` after a
build). Kept for continuity — the noun-bundle editorial decisions in
`nouns.yaml` trace back to these runs.

## Findings from run 2026-07-03 (queries/demo.sql, Utah)

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
