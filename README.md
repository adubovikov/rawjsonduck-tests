# rawjsonduck-tests

Test suite and benchmarks for [RawDuck](https://github.com/quackscience/rawduck) — schema-less JSON ingestion and analytics for DuckDB.

Compares **RawDuck shredded typed columns** against opaque **JSON**, **VARCHAR**, and **BLOB** storage: **write speed**, **read speed**, and **on-disk size**.

## Requirements

- Linux or macOS (x86_64 / arm64)
- `curl`, `python3`, `bash`

RawDuck **v0.0.2** (DuckDB 1.5.3) is installed into `bin/` by `scripts/setup.sh`.

## Quick start

```bash
git clone https://github.com/adubovikov/rawjsonduck-tests.git
cd rawjsonduck-tests

./scripts/setup.sh
./scripts/run_all_tests.sh
```

## Tests

| File | Description |
|------|-------------|
| `sql/01_basic_attach.sql` | `ATTACH` + ingest lane `INSERT` |
| `sql/02_raw_ingest.sql` | `CALL raw_ingest()` |
| `sql/03_schema_evolution.sql` | New JSON keys → new columns |
| `sql/04_ndjson_file.sql` | `raw_ingest_file()` |
| `sql/05_otlp_traces.sql` | OTLP `otlp-traces` transform |
| `sql/06_type_inference.sql` | `raw_type` / `raw_infer` |
| `sql/07_async_insert.sql` | Async buffer + `raw_flush` |
| `sql/08_raw_records.sql` | Parse without touching tables |
| `scripts/test_compare_storage.sh` | Write / read / disk benchmark |
| `scripts/test_compare_storage_scale.sh` | 100k + 500k scale benchmark |
| `scripts/test_http.sh` | HTTP API smoke test |

SQL files use `{{ROOT}}` placeholders; runners substitute the repo root automatically.

## Storage benchmark

```bash
./scripts/test_compare_storage.sh            # 50,000 rows (default)
./scripts/test_compare_storage.sh 100000     # 100k rows
./scripts/test_compare_storage.sh 500000     # 500k rows
./scripts/test_compare_storage_scale.sh      # 100k + 500k back-to-back
```

Prints DuckDB tables: write speed, read speed (per query + average), disk size, and a combined summary.
Results are saved with scale-specific filenames (e.g. `10_compare_bench_100k.txt`).

Full log: [`results/sample/benchmark_50k.txt`](results/sample/benchmark_50k.txt)

### Results summary (50,000 rows, ~6.1 MB NDJSON, Linux x86_64, best of 3 runs)

| Storage | Write (ms) | Write rows/s | Read avg (ms) | Disk (MB) | Write × | Read × | Disk × |
|---------|------------|--------------|---------------|-----------|---------|--------|--------|
| **rawduck** | 102 | 490,196 | 20.0 | 1.01 | 1.0 | 1.0 | 1.0 |
| json | 80 | 625,000 | 35.3 | 2.01 | 0.78 | 1.77 | 1.99 |
| varchar | 72 | 694,444 | 34.3 | 2.01 | 0.71 | 1.72 | 1.99 |
| blob | 82 | 609,756 | 35.5 | 2.01 | 0.80 | 1.78 | 1.99 |

### At scale: 100k and 500k rows

At small scale (100k), RawDuck pays ~25–33% write overhead for shredding but reads 2–2.6× faster and uses 2× less disk.
At 500k+ rows, columnar compression amortizes the shredding cost — RawDuck writes **25% faster** than opaque storage while reading 2.4–3.5× faster and using 2.8× less disk.

Write × / Read × / Disk × are relative to RawDuck (`< 1` on Write × = faster write than RawDuck; `> 1` on Read/Disk × = slower or larger).

**Takeaway:** opaque types win on **write** at small scale; RawDuck wins on **read** (~1.7–3.5×) and **disk** (~2–2.8× smaller). The crossover where RawDuck also wins on write is around 200k–500k rows. See [RawDuck BENCHMARK.md](https://github.com/quackscience/rawduck/blob/main/BENCHMARK.md).

## Links

- [RawDuck](https://github.com/quackscience/rawduck)
- [DuckDB community extension](https://duckdb.org/community_extensions/extensions/rawduck)
