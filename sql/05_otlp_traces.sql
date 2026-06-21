-- Test: OTLP traces transform
ATTACH 'rawduck:{{ROOT}}/results/05_otlp.db' AS raw;

CALL raw_ingest_file('traces', '{{ROOT}}/data/otlp_traces.ndjson', transform := 'otlp-traces');

SELECT count(*) AS span_count FROM traces;

SELECT "resource.service.name", "http.status_code", count(*) AS n
FROM traces
GROUP BY 1, 2
ORDER BY 1, 2;

SELECT count(*) AS error_spans
FROM traces
WHERE "http.status_code" >= 500;
