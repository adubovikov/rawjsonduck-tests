-- Test: schema evolves when new JSON keys appear
ATTACH 'rawduck:{{ROOT}}/results/03_evolution.db' AS raw;

INSERT INTO raw.ingest.events VALUES
    ('{"id": 1, "action": "click", "user": {"name": "alice", "plan": "pro"}}');

INSERT INTO raw.ingest.events VALUES
    ('{"id": 2, "action": "view", "user": {"name": "bob", "error": "timeout"}}');

DESCRIBE raw.events;

SELECT id, action, "user.name", "user.plan", "user.error"
FROM raw.events
ORDER BY id;
