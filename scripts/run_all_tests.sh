#!/usr/bin/env bash
# Run all RawDuck SQL tests, storage benchmark, and HTTP test.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/bin/rawduck"
SQL_DIR="$ROOT/sql"
RESULTS="$ROOT/results"
SUMMARY="$RESULTS/summary.txt"

mkdir -p "$RESULTS"

if [[ ! -x "$BIN" ]]; then
    echo "Installing RawDuck..."
    "$ROOT/scripts/setup.sh"
fi

echo "Using: $BIN ($("$BIN" --version))"
echo "Results: $RESULTS"
echo ""

PASS=0
FAIL=0
FAILED_TESTS=()

run_sql_test() {
    local name="$1"
    local sql_file="$2"
    local out_file="$RESULTS/${name}.log"

    echo "==> SQL: $name"

    if sed "s|{{ROOT}}|${ROOT}|g" "$sql_file" | "$BIN" -f /dev/stdin >"$out_file" 2>&1; then
        echo "    PASS"
        ((PASS++)) || true
    else
        echo "    FAIL (see $out_file)"
        ((FAIL++)) || true
        FAILED_TESTS+=("$name")
    fi
}

for f in "$SQL_DIR"/*.sql; do
    base=$(basename "$f" .sql)
    run_sql_test "$base" "$f"
done

echo "==> Benchmark: 10_compare_storage"
if "$ROOT/scripts/test_compare_storage.sh"; then
    echo "    PASS"
    ((PASS++)) || true
else
    echo "    FAIL (see $RESULTS/10_compare_storage.log)"
    ((FAIL++)) || true
    FAILED_TESTS+=("10_compare_storage")
fi

echo "==> HTTP: 09_http"
if "$ROOT/scripts/test_http.sh"; then
    echo "    PASS"
    ((PASS++)) || true
else
    echo "    FAIL (see $RESULTS/09_http.log)"
    ((FAIL++)) || true
    FAILED_TESTS+=("09_http")
fi

echo ""
echo "========================================"
{
    echo "RawDuck test run: $(date -Iseconds)"
    echo "Binary: $BIN"
    echo "Passed: $PASS"
    echo "Failed: $FAIL"
    if [[ ${#FAILED_TESTS[@]} -gt 0 ]]; then
        echo "Failed tests: ${FAILED_TESTS[*]}"
    fi
} | tee "$SUMMARY"

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi

echo "All tests passed."
