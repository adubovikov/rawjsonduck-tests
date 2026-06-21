#!/usr/bin/env bash
# Start HTTP server in background, run curl checks, stop server.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/bin/rawduck"
PORT=19999
TOKEN="ducktest_token"
LOG="$ROOT/results/09_http_server.log"
OUT="$ROOT/results/09_http.log"
FIFO="$ROOT/results/.http_fifo"

if [[ ! -x "$BIN" ]]; then
    echo "Run scripts/setup.sh first"
    exit 1
fi

rm -f "$LOG" "$OUT" "$FIFO"
touch "$OUT"
mkfifo "$FIFO"

cleanup() {
    exec 4>&- 2>/dev/null || true
    if [[ -n "${SERVER_PID:-}" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
        kill -TERM "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
    rm -f "$FIFO"
}
trap cleanup EXIT

"$BIN" <"$FIFO" >"$LOG" 2>&1 &
SERVER_PID=$!

exec 4>"$FIFO"
echo "CALL raw_serve(host := '127.0.0.1', port := ${PORT}, token := '${TOKEN}');" >&4

# Wait for server
for i in $(seq 1 50); do
    if curl -sf "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; then
        break
    fi
    sleep 0.2
done

if ! curl -sf "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; then
    echo "FAIL: HTTP server did not start" | tee -a "$OUT"
    cat "$LOG"
    exit 1
fi

pass() { echo "PASS: $1" | tee -a "$OUT"; }
fail() { echo "FAIL: $1" | tee -a "$OUT"; exit 1; }

HEALTH=$(curl -sf "http://127.0.0.1:${PORT}/health")
[[ "$HEALTH" == *"ok"* ]] && pass "GET /health" || fail "GET /health -> $HEALTH"

INS=$(curl -sf -X POST "http://127.0.0.1:${PORT}/v1/tables/http_events" \
    -H "Authorization: Bearer ${TOKEN}" \
    -d '[{"action":"click","user":"alice","value":42}]')
[[ "$INS" == *"inserted"* ]] && pass "POST /v1/tables/http_events" || fail "ingest -> $INS"

QRY=$(curl -sf -X POST "http://127.0.0.1:${PORT}/v1/query" \
    -H "Authorization: Bearer ${TOKEN}" \
    -d '{"sql":"SELECT action, count(*) AS n FROM http_events GROUP BY action"}')
[[ "$QRY" == *"click"* ]] && pass "POST /v1/query" || fail "query -> $QRY"

TBL=$(curl -sf "http://127.0.0.1:${PORT}/v1/tables" \
    -H "Authorization: Bearer ${TOKEN}")
[[ "$TBL" == *"http_events"* ]] && pass "GET /v1/tables" || fail "tables -> $TBL"

echo "All HTTP checks passed." | tee -a "$OUT"
