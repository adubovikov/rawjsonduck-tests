#!/usr/bin/env bash
# Run the storage comparison benchmark at 100k and 500k row scales.
# Results are saved under results/ with scale-specific filenames.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "======================================"
echo "  RawDuck Storage Benchmark: 100k rows"
echo "======================================"
"$ROOT/scripts/test_compare_storage.sh" 100000

echo ""
echo "======================================"
echo "  RawDuck Storage Benchmark: 500k rows"
echo "======================================"
"$ROOT/scripts/test_compare_storage.sh" 500000

echo ""
echo "All scale benchmarks complete."
