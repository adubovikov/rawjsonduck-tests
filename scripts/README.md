# Scripts

Test runners, benchmarks, and utilities for the RawDuck test suite.

## Setup

| Script | Description |
|--------|-------------|
| `setup.sh` | Download and install RawDuck v0.0.2 (DuckDB 1.5.3) into `bin/`. Auto-detects platform (Linux/macOS, x86_64/arm64). Idempotent — skips download if already installed. |

## Test runners

| Script | Description |
|--------|-------------|
| `run_all_tests.sh` | Run every SQL test, the storage benchmark, and the HTTP smoke test. Prints a pass/fail summary and exits non-zero on any failure. Calls `setup.sh` automatically if the binary is missing. |

## Benchmarks

| Script | Description |
|--------|-------------|
| `test_compare_storage.sh [ROWS]` | Compare RawDuck shredded columns vs JSON, VARCHAR, and BLOB storage. Measures write speed (best of 3), read speed (4 queries, best of 3 each), and on-disk size. Default: 50,000 rows. Results saved to `results/` with scale-specific filenames when ROWS differs from default. |
| `test_compare_storage_scale.sh` | Run `test_compare_storage.sh` at 100k and 500k rows back-to-back. |

### Examples

```bash
./scripts/test_compare_storage.sh              # 50k rows (default)
./scripts/test_compare_storage.sh 100000       # 100k rows
./scripts/test_compare_storage.sh 500000       # 500k rows
./scripts/test_compare_storage.sh 1000000      # 1M rows
./scripts/test_compare_storage_scale.sh        # 100k + 500k
```

### Output files

Results are written to `results/` with scale-specific naming:

| File pattern | Content |
|---|---|
| `10_compare_bench_{N}k.txt` | Human-readable benchmark tables |
| `10_compare_write_{N}k.csv` | Write times and disk sizes (CSV) |
| `10_compare_read_{N}k.csv` | Per-query read times (CSV) |
| `10_compare_disk_{N}k.csv` | On-disk sizes (CSV) |
| `10_compare_storage_{N}k.log` | Full run log |

## HTTP test

| Script | Description |
|--------|-------------|
| `test_http.sh` | Start the RawDuck HTTP server in background, run curl-based smoke tests (health, ingest, query, list tables), then stop. Uses port 19999. |

## Data generator

| Script | Description |
|--------|-------------|
| `gen_compare_data.py [ROWS]` | Generate NDJSON test data for the storage benchmark. Produces deterministic output (seed=42) with nested objects (`user.name`, `user.plan`), mixed types, and 5 action categories. Default: 50,000 rows. Output: `data/compare_events.ndjson`. Called automatically by `test_compare_storage.sh`. |
