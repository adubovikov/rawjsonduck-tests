-- Test: parse without touching tables
SELECT * FROM raw_records('[{"x": 1, "y": {"z": "ok"}}, {"x": 2}]');
