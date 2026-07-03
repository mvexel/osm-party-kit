-- osmlogo v0 — the seven demo queries over cosmo-produced GeoParquet.
-- Run: duckdb -c ".read queries/demo.sql" from the osmlogo dir.
INSTALL spatial; LOAD spatial;

CREATE VIEW parks       AS SELECT * FROM 'out/parks.parquet';
CREATE VIEW benches     AS SELECT * FROM 'out/benches.parquet';
CREATE VIEW toilets     AS SELECT * FROM 'out/toilets.parquet';
CREATE VIEW museums     AS SELECT * FROM 'out/museums.parquet';
CREATE VIEW shops       AS SELECT * FROM 'out/shops.parquet';
CREATE VIEW restaurants AS SELECT * FROM 'out/restaurants.parquet';
CREATE VIEW crossings   AS SELECT * FROM 'out/crossings.parquet';
CREATE VIEW buildings   AS SELECT * FROM 'out/buildings.parquet';
CREATE VIEW playgrounds AS SELECT * FROM 'out/playgrounds.parquet';
CREATE VIEW boundaries  AS SELECT * FROM 'out/boundaries.parquet';

-- Named places ("IN <place>" dropdown)
CREATE VIEW slc AS SELECT geometry FROM boundaries WHERE name = 'Salt Lake City' LIMIT 1;
CREATE VIEW park_city AS SELECT geometry FROM boundaries WHERE name = 'Park City' LIMIT 1;

.print === 1. MUSEUMS WITHOUT OPENING_HOURS IN SALT_LAKE_CITY ===
SELECT m.name, m.website
FROM museums m, slc
WHERE ST_Within(m.geometry, slc.geometry)
  AND m.opening_hours IS NULL
ORDER BY m.name;

.print === 2. PARKS CONTAINING NO BENCHES (statewide, named parks) ===
SELECT count(*) AS parks_without_benches,
       (SELECT count(*) FROM parks WHERE name IS NOT NULL) AS total_named_parks
FROM parks p
WHERE p.name IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM benches b WHERE ST_Intersects(b.geometry, p.geometry)
  );

.print === 2b. ...the 15 largest offenders ===
SELECT p.name, round(ST_Area(p.geometry::GEOMETRY) * 1e6, 1) AS rel_size
FROM parks p
WHERE p.name IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM benches b WHERE ST_Intersects(b.geometry, p.geometry))
ORDER BY ST_Area(p.geometry::GEOMETRY) DESC
LIMIT 15;

.print === 3. PLAYGROUNDS WITH NO TOILET WITHIN ~150M ===
SELECT count(*) AS playgrounds_no_nearby_toilet,
       (SELECT count(*) FROM playgrounds) AS total_playgrounds
FROM playgrounds pg
WHERE NOT EXISTS (
  SELECT 1 FROM toilets t
  WHERE ST_DWithin(t.geometry::GEOMETRY, pg.geometry::GEOMETRY, 0.0015)
);

.print === 4. SHOPS OLDER_THAN 2 YEARS IN PARK_CITY ===
SELECT count(*) AS stale, (
    SELECT count(*) FROM shops s2, park_city
    WHERE ST_Within(s2.geometry, park_city.geometry)
  ) AS total_shops
FROM shops s, park_city
WHERE ST_Within(s.geometry, park_city.geometry)
  AND s.timestamp < '2024-07-03';

.print === 4b. ...oldest 15 ===
SELECT s.name, s.shop, s.timestamp
FROM shops s, park_city
WHERE ST_Within(s.geometry, park_city.geometry)
  AND s.timestamp < '2024-07-03'
ORDER BY s.timestamp
LIMIT 15;

.print === 5. CROSSINGS WITHOUT LIT IN SALT_LAKE_CITY ===
SELECT coalesce(c.lit, '(no lit tag)') AS lit, count(*) AS n
FROM crossings c, slc
WHERE ST_Within(c.geometry, slc.geometry)
GROUP BY 1 ORDER BY n DESC;

.print === 6. BUILDINGS WITHOUT ADDRESS IN SALT_LAKE_CITY ===
SELECT count(*) FILTER (housenumber IS NULL) AS no_address,
       count(*) AS total,
       round(100.0 * count(*) FILTER (housenumber IS NULL) / count(*), 1) AS pct_missing
FROM buildings b, slc
WHERE ST_Within(b.geometry, slc.geometry);

.print === 7. RESTAURANTS EDITED_SINCE 1 MONTH (statewide) ===
SELECT count(*) AS edited_last_month FROM restaurants WHERE timestamp >= '2026-06-03';

.print === 7b. ...most recent 15 ===
SELECT name, timestamp FROM restaurants
WHERE timestamp >= '2026-06-03' AND name IS NOT NULL
ORDER BY timestamp DESC LIMIT 15;
