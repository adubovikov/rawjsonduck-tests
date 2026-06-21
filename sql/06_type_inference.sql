-- Test: raw_type and raw_infer helpers
SELECT raw_type('42') AS t_int;
SELECT raw_type('hello') AS t_str;
SELECT raw_type('true') AS t_bool;
SELECT raw_infer('{"a": 1, "b": {"c": "x"}}') AS inferred;
