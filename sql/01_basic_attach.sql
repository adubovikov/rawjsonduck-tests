-- Test: ATTACH rawduck store + INSERT via ingest lane
ATTACH 'rawduck:{{ROOT}}/results/01_basic.db' AS raw;

INSERT INTO raw.ingest.events VALUES
    ('{"id": 1, "action": "click", "ts": "2024-01-15T10:30:00", "user": {"name": "alice", "plan": "pro"}}'),
    ('{"id": 2, "action": "view",  "ts": "2024-01-15T10:31:00", "user": {"name": "bob"}}');

DESCRIBE raw.events;

SELECT "user.name", count(*) AS n FROM raw.events GROUP BY 1 ORDER BY 1;

SELECT count(*) AS row_count FROM raw.events;
