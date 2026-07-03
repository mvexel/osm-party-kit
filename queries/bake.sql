-- Bake step: precompute ALL spatial work so the browser needs no spatial engine.
-- Input:  out/*.parquet   (raw cosmo output, geoparquet)
-- Output: baked/*.parquet (place-assigned, proximity-counted, lon/lat, no geometry)
--         web/boundaries.geojson (simplified, display only)
--         web/places.json (place dropdown)
-- Run: duckdb -c ".read queries/bake.sql" from the osmlogo dir.

INSTALL spatial; LOAD spatial;

-- Full-resolution boundaries for assignment (never simplified here).
CREATE TABLE bounds AS
SELECT name, geometry FROM 'out/boundaries.parquet' WHERE name IS NOT NULL;

-- Assign by centroid so polygon features straddling a boundary get one place.
CREATE MACRO place_of(g) AS (
  SELECT b.name FROM bounds b
  WHERE ST_Contains(b.geometry::GEOMETRY, ST_Centroid(g::GEOMETRY))
  LIMIT 1
);
CREATE MACRO lon_of(g) AS ST_X(ST_Centroid(g::GEOMETRY));
CREATE MACRO lat_of(g) AS ST_Y(ST_Centroid(g::GEOMETRY));

-- Point-ish nouns: place + lon/lat, drop geometry.
COPY (SELECT s.* EXCLUDE (geometry), lon_of(s.geometry) AS lon, lat_of(s.geometry) AS lat, place_of(s.geometry) AS place FROM 'out/shops.parquet' s)          TO 'baked/shops.parquet' (FORMAT PARQUET);
COPY (SELECT s.* EXCLUDE (geometry), lon_of(s.geometry) AS lon, lat_of(s.geometry) AS lat, place_of(s.geometry) AS place FROM 'out/restaurants.parquet' s)    TO 'baked/restaurants.parquet' (FORMAT PARQUET);
COPY (SELECT s.* EXCLUDE (geometry), lon_of(s.geometry) AS lon, lat_of(s.geometry) AS lat, place_of(s.geometry) AS place FROM 'out/museums.parquet' s)        TO 'baked/museums.parquet' (FORMAT PARQUET);
COPY (SELECT s.* EXCLUDE (geometry), lon_of(s.geometry) AS lon, lat_of(s.geometry) AS lat, place_of(s.geometry) AS place FROM 'out/libraries.parquet' s)      TO 'baked/libraries.parquet' (FORMAT PARQUET);
COPY (SELECT s.* EXCLUDE (geometry), lon_of(s.geometry) AS lon, lat_of(s.geometry) AS lat, place_of(s.geometry) AS place FROM 'out/toilets.parquet' s)        TO 'baked/toilets.parquet' (FORMAT PARQUET);
COPY (SELECT s.* EXCLUDE (geometry), lon_of(s.geometry) AS lon, lat_of(s.geometry) AS lat, place_of(s.geometry) AS place FROM 'out/benches.parquet' s)        TO 'baked/benches.parquet' (FORMAT PARQUET);
COPY (SELECT s.* EXCLUDE (geometry), lon_of(s.geometry) AS lon, lat_of(s.geometry) AS lat, place_of(s.geometry) AS place FROM 'out/drinking_water.parquet' s) TO 'baked/drinking_water.parquet' (FORMAT PARQUET);
COPY (SELECT s.* EXCLUDE (geometry), lon_of(s.geometry) AS lon, lat_of(s.geometry) AS lat, place_of(s.geometry) AS place FROM 'out/bus_stops.parquet' s)      TO 'baked/bus_stops.parquet' (FORMAT PARQUET);
COPY (SELECT s.* EXCLUDE (geometry), lon_of(s.geometry) AS lon, lat_of(s.geometry) AS lat, place_of(s.geometry) AS place FROM 'out/crossings.parquet' s)      TO 'baked/crossings.parquet' (FORMAT PARQUET);
COPY (SELECT s.* EXCLUDE (geometry), lon_of(s.geometry) AS lon, lat_of(s.geometry) AS lat, place_of(s.geometry) AS place FROM 'out/buildings.parquet' s)      TO 'baked/buildings.parquet' (FORMAT PARQUET);

-- Container nouns: place + lon/lat + proximity-count matrix.
COPY (
  SELECT p.* EXCLUDE (geometry), lon_of(p.geometry) AS lon, lat_of(p.geometry) AS lat, place_of(p.geometry) AS place,
    (SELECT count(*) FROM 'out/benches.parquet' b
      WHERE ST_Intersects(b.geometry::GEOMETRY, p.geometry::GEOMETRY)) AS bench_count,
    (SELECT count(*) FROM 'out/toilets.parquet' t
      WHERE ST_Intersects(t.geometry::GEOMETRY, p.geometry::GEOMETRY)) AS toilet_count,
    (SELECT count(*) FROM 'out/playgrounds.parquet' g
      WHERE ST_Intersects(g.geometry::GEOMETRY, p.geometry::GEOMETRY)) AS playground_count
  FROM 'out/parks.parquet' p
) TO 'baked/parks.parquet' (FORMAT PARQUET);

COPY (
  SELECT pg.* EXCLUDE (geometry), lon_of(pg.geometry) AS lon, lat_of(pg.geometry) AS lat, place_of(pg.geometry) AS place,
    (SELECT count(*) FROM 'out/toilets.parquet' t
      WHERE ST_DWithin(t.geometry::GEOMETRY, pg.geometry::GEOMETRY, 0.0015)) AS toilets_within_150m,
    (SELECT count(*) FROM 'out/drinking_water.parquet' w
      WHERE ST_DWithin(w.geometry::GEOMETRY, pg.geometry::GEOMETRY, 0.0015)) AS water_within_150m,
    (SELECT count(*) FROM 'out/benches.parquet' b
      WHERE ST_DWithin(b.geometry::GEOMETRY, pg.geometry::GEOMETRY, 0.0015)) AS benches_within_150m
  FROM 'out/playgrounds.parquet' pg
) TO 'baked/playgrounds.parquet' (FORMAT PARQUET);

COPY (
  SELECT s.* EXCLUDE (geometry), lon_of(s.geometry) AS lon, lat_of(s.geometry) AS lat, place_of(s.geometry) AS place,
    (SELECT count(*) FROM 'out/crossings.parquet' c
      WHERE ST_DWithin(c.geometry::GEOMETRY, s.geometry::GEOMETRY, 0.0015)) AS crossings_within_150m,
    (SELECT count(*) FROM 'out/bus_stops.parquet' bs
      WHERE ST_DWithin(bs.geometry::GEOMETRY, s.geometry::GEOMETRY, 0.0015)) AS bus_stops_within_150m
  FROM 'out/schools.parquet' s
) TO 'baked/schools.parquet' (FORMAT PARQUET);

-- Display-only boundaries: simplified hard, GeoJSON for the map. Never used for assignment.
COPY (
  SELECT name, ST_SimplifyPreserveTopology(geometry::GEOMETRY, 0.001) AS geom
  FROM 'out/boundaries.parquet' WHERE name IS NOT NULL
) TO 'web/boundaries.geojson' WITH (FORMAT GDAL, DRIVER 'GeoJSON');

-- Place dropdown.
COPY (SELECT DISTINCT name FROM bounds ORDER BY name) TO 'web/places.json' (FORMAT JSON, ARRAY true);
