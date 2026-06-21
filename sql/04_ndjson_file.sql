-- Test: raw_ingest_file from NDJSON
ATTACH 'rawduck:{{ROOT}}/results/04_file.db' AS raw;

CALL raw_ingest_file('raw.events', '{{ROOT}}/data/events.ndjson');

SELECT count(*) AS row_count FROM raw.events;

SELECT id, action, "user.name", amount
FROM raw.events
ORDER BY id;
