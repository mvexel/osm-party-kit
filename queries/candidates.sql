-- Candidate mapper queries, round 2
INSTALL spatial; LOAD spatial;
CREATE VIEW bus_stops AS SELECT * FROM 'out/bus_stops.parquet';
CREATE VIEW restaurants AS SELECT * FROM 'out/restaurants.parquet';
CREATE VIEW shops AS SELECT * FROM 'out/shops.parquet';
CREATE VIEW crossings AS SELECT * FROM 'out/crossings.parquet';
CREATE VIEW schools AS SELECT * FROM 'out/schools.parquet';

.print === BUS_STOPS WITHOUT SHELTER / BENCH / NAME (statewide) ===
SELECT count(*) AS total,
  count(*) FILTER (shelter IS NULL) AS no_shelter_tag,
  count(*) FILTER (bench IS NULL) AS no_bench_tag,
  count(*) FILTER (name IS NULL) AS no_name
FROM bus_stops;

.print === RESTAURANTS WITHOUT CUISINE ===
SELECT count(*) FILTER (cuisine IS NULL) AS no_cuisine, count(*) AS total FROM restaurants;

.print === RESTAURANTS WITH WEBSITE BUT WITHOUT OPENING_HOURS ===
SELECT count(*) AS website_but_no_hours FROM restaurants WHERE website IS NOT NULL AND opening_hours IS NULL;

.print === SHOPS WITHOUT NAME ===
SELECT count(*) FILTER (name IS NULL) AS unnamed, count(*) AS total FROM shops;

.print === SHOPS NEVER EDITED SINCE CREATION, OLDER THAN 3 YEARS ===
SELECT count(*) AS mapped_once_forgotten FROM shops WHERE version = 1 AND timestamp < '2023-07-03';

.print === CROSSINGS WITHOUT TACTILE_PAVING (statewide) ===
SELECT count(*) FILTER (tactile_paving IS NULL) AS untagged, count(*) AS total FROM crossings;

.print === SCHOOLS WITH NO CROSSING WITHIN ~150M ===
SELECT count(*) AS schools_no_crossing, (SELECT count(*) FROM schools WHERE name IS NOT NULL) AS total
FROM schools s
WHERE s.name IS NOT NULL AND NOT EXISTS (
  SELECT 1 FROM crossings c WHERE ST_DWithin(c.geometry::GEOMETRY, s.geometry::GEOMETRY, 0.0015));

.print === DUPLICATE-NAME RESTAURANT PAIRS WITHIN ~100M ===
SELECT count(*) AS dup_pairs FROM restaurants a JOIN restaurants b
  ON a.name = b.name AND a.osm_id < b.osm_id
  AND ST_DWithin(a.geometry::GEOMETRY, b.geometry::GEOMETRY, 0.001)
WHERE a.name IS NOT NULL;
