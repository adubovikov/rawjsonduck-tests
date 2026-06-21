-- Test: raw_ingest() without ATTACH
CALL raw_ingest('events2', '[{"id": 1, "action": "click"}, {"id": 2, "action": "view"}]');

SELECT * FROM events2 ORDER BY id;

SELECT count(*) AS row_count FROM events2;
