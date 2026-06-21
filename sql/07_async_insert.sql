-- Test: async insert + flush
SET rawduck_async_insert = true;

CALL raw_ingest('async_events', '[{"id": 1, "v": "a"}]');
CALL raw_ingest('async_events', '[{"id": 2, "v": "b"}]');

CALL raw_flush();

SELECT count(*) AS row_count FROM async_events;

RESET rawduck_async_insert;
