-- Bake step: precompute spatial relations so the browser never does spatial work.
-- Input:  out/*.parquet   (raw cosmo output)
-- Output: baked/*.parquet (place-assigned, proximity-counted)
--         baked/boundaries_display.parquet (simplified, for map rendering only)
-- Run: duckdb -c ".read queries/bake.sql" from the osmlogo dir.

INSTALL spatial; LOAD spatial;

-- Full-resolution boundaries for assignment (never simplified here).
CREATE TABLE bounds AS
SELECT name, geometry FROM 'out/boundaries.parquet' WHERE name IS NOT NULL;

-- place(geom): assign by centroid so polygon features straddling a boundary
-- get exactly one place.
CREATE MACRO place_of(g) AS (
  SELECT b.name FROM bounds b
  WHERE ST_Contains(b.geometry::GEOMETRY, ST_Centroid(g::GEOMETRY))
  LIMIT 1
);

-- Point-ish nouns: just add place.
COPY (SELECT s.*, place_of(s.geometry) AS place FROM 'out/shops.parquet' s)          TO 'baked/shops.parquet' (FORMAT PARQUET);
COPY (SELECT s.*, place_of(s.geometry) AS place FROM 'out/restaurants.parquet' s)    TO 'baked/restaurants.parquet' (FORMAT PARQUET);
COPY (SELECT s.*, place_of(s.geometry) AS place FROM 'out/museums.parquet' s)        TO 'baked/museums.parquet' (FORMAT PARQUET);
COPY (SELECT s.*, place_of(s.geometry) AS place FROM 'out/libraries.parquet' s)      TO 'baked/libraries.parquet' (FORMAT PARQUET);
COPY (SELECT s.*, place_of(s.geometry) AS place FROM 'out/toilets.parquet' s)        TO 'baked/toilets.parquet' (FORMAT PARQUET);
COPY (SELECT s.*, place_of(s.geometry) AS place FROM 'out/benches.parquet' s)        TO 'baked/benches.parquet' (FORMAT PARQUET);
COPY (SELECT s.*, place_of(s.geometry) AS place FROM 'out/drinking_water.parquet' s) TO 'baked/drinking_water.parquet' (FORMAT PARQUET);
COPY (SELECT s.*, place_of(s.geometry) AS place FROM 'out/bus_stops.parquet' s)      TO 'baked/bus_stops.parquet' (FORMAT PARQUET);
COPY (SELECT s.*, place_of(s.geometry) AS place FROM 'out/crossings.parquet' s)      TO 'baked/crossings.parquet' (FORMAT PARQUET);
COPY (SELECT s.*, place_of(s.geometry) AS place FROM 'out/buildings.parquet' s)      TO 'baked/buildings.parquet' (FORMAT PARQUET);

-- Container nouns: place + proximity-count matrix.
-- parks: benches/toilets that intersect the park polygon.
COPY (
  SELECT p.*, place_of(p.geometry) AS place,
    (SELECT count(*) FROM 'out/benches.parquet' b
      WHERE ST_Intersects(b.geometry::GEOMETRY, p.geometry::GEOMETRY)) AS bench_count,
    (SELECT count(*) FROM 'out/toilets.parquet' t
      WHERE ST_Intersects(t.geometry::GEOMETRY, p.geometry::GEOMETRY)) AS toilet_count
  FROM 'out/parks.parquet' p
) TO 'baked/parks.parquet' (FORMAT PARQUET);

-- playgrounds: toilets and drinking water within ~150 m (0.0015 deg at this latitude).
COPY (
  SELECT pg.*, place_of(pg.geometry) AS place,
    (SELECT count(*) FROM 'out/toilets.parquet' t
      WHERE ST_DWithin(t.geometry::GEOMETRY, pg.geometry::GEOMETRY, 0.0015)) AS toilets_within_150m,
    (SELECT count(*) FROM 'out/drinking_water.parquet' w
      WHERE ST_DWithin(w.geometry::GEOMETRY, pg.geometry::GEOMETRY, 0.0015)) AS water_within_150m,
    (SELECT count(*) FROM 'out/benches.parquet' b
      WHERE ST_DWithin(b.geometry::GEOMETRY, pg.geometry::GEOMETRY, 0.0015)) AS benches_within_150m
  FROM 'out/playgrounds.parquet' pg
) TO 'baked/playgrounds.parquet' (FORMAT PARQUET);

-- schools: crossings and bus stops within ~150 m.
COPY (
  SELECT s.*, place_of(s.geometry) AS place,
    (SELECT count(*) FROM 'out/crossings.parquet' c
      WHERE ST_DWithin(c.geometry::GEOMETRY, s.geometry::GEOMETRY, 0.0015)) AS crossings_within_150m,
    (SELECT count(*) FROM 'out/bus_stops.parquet' bs
      WHERE ST_DWithin(bs.geometry::GEOMETRY, s.geometry::GEOMETRY, 0.0015)) AS bus_stops_within_150m
  FROM 'out/schools.parquet' s
) TO 'baked/schools.parquet' (FORMAT PARQUET);

-- Display-only boundaries: simplified hard, never used for assignment.
COPY (
  SELECT name, admin_level, osm_id,
         ST_SimplifyPreserveTopology(geometry::GEOMETRY, 0.001) AS geometry
  FROM 'out/boundaries.parquet' WHERE name IS NOT NULL
) TO 'baked/boundaries_display.parquet' (FORMAT PARQUET);
