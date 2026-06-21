#!/usr/bin/env bash
# Benchmark: write speed, read speed, and on-disk size —
# RawDuck shredded columns vs JSON / VARCHAR / BLOB opaque storage.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/bin/rawduck"
NDJSON="$ROOT/data/compare_events.ndjson"
OUT="$ROOT/results/10_compare_storage.log"
BENCH="$ROOT/results/10_compare_bench.txt"
WRITE_CSV="$ROOT/results/10_compare_write.csv"
READ_CSV="$ROOT/results/10_compare_read.csv"
DISK_CSV="$ROOT/results/10_compare_disk.csv"

RAW_DB="$ROOT/results/10_bench_rawduck.db"
JSON_DB="$ROOT/results/10_bench_json.duckdb"
VARCHAR_DB="$ROOT/results/10_bench_varchar.duckdb"
BLOB_DB="$ROOT/results/10_bench_blob.duckdb"

READ_CSV_SQL="read_csv('${NDJSON}', header=false, delim='\n', quote='', escape='', columns={line: 'VARCHAR'})"

mkdir -p "$ROOT/results"

if [[ ! -x "$BIN" ]]; then
    echo "Run scripts/setup.sh first"
    exit 1
fi

# Clean previous benchmark artifacts
rm -f "$RAW_DB" "$JSON_DB" "$VARCHAR_DB" "$BLOB_DB"
rm -f "${RAW_DB}.wal" "${JSON_DB}.wal" "${VARCHAR_DB}.wal" "${BLOB_DB}.wal"

print_table() {
    local title="$1"
    local sql="$2"
    echo ""
    echo "$title"
    "$BIN" -c "$sql" 2>/dev/null
}

time_best_of_3() {
    local cmd="$1"
    local best=999999999
    local i start end ms

    for i in 1 2 3; do
        start=$(date +%s%N)
        eval "$cmd"
        end=$(date +%s%N)
        ms=$(( (end - start) / 1000000 ))
        if (( ms < best )); then best=$ms; fi
    done
    echo "$best"
}

file_bytes() {
    local path="$1"
    if [[ -f "$path" ]]; then
        stat -c '%s' "$path"
    else
        echo 0
    fi
}

bench_read_ms() {
    local db="$1"
    local attach="$2"
    local query="$3"
    local best=999999999
    local i start end ms sql

    sql="${attach} ${query}"
    for i in 1 2 3; do
        start=$(date +%s%N)
        if [[ -n "$db" ]]; then
            "$BIN" "$db" -csv -c "$sql" >/dev/null 2>&1
        else
            "$BIN" -csv -c "$sql" >/dev/null 2>&1
        fi
        end=$(date +%s%N)
        ms=$(( (end - start) / 1000000 ))
        if (( ms < best )); then best=$ms; fi
    done
    echo "$best"
}

ROWS="${1:-50000}"
python3 "$ROOT/scripts/gen_compare_data.py" "$ROWS"
SOURCE_BYTES=$(file_bytes "$NDJSON")
SOURCE_MB=$(awk "BEGIN {printf \"%.2f\", $SOURCE_BYTES / 1048576}")

echo "==> Compare storage: write + read + disk" | tee "$OUT"
echo "Rows: $ROWS | Source NDJSON: ${SOURCE_MB} MB ($SOURCE_BYTES bytes)" | tee -a "$OUT"

# --- Write benchmarks (isolated DB per storage type) ---
write_rawduck() {
    rm -f "$RAW_DB" "${RAW_DB}.wal"
    "$BIN" -c "
        ATTACH 'rawduck:${RAW_DB}' AS raw;
        CALL raw_ingest_file('raw.events', '${NDJSON}');
        CHECKPOINT;
    " >/dev/null 2>&1
}

write_json() {
    rm -f "$JSON_DB" "${JSON_DB}.wal"
    "$BIN" "$JSON_DB" -c "
        CREATE TABLE events_json AS
        SELECT line::JSON AS j
        FROM ${READ_CSV_SQL}
        WHERE length(line) > 0;
        CHECKPOINT;
    " >/dev/null 2>&1
}

write_varchar() {
    rm -f "$VARCHAR_DB" "${VARCHAR_DB}.wal"
    "$BIN" "$VARCHAR_DB" -c "
        CREATE TABLE events_varchar AS
        SELECT line AS s
        FROM ${READ_CSV_SQL}
        WHERE length(line) > 0;
        CHECKPOINT;
    " >/dev/null 2>&1
}

write_blob() {
    rm -f "$BLOB_DB" "${BLOB_DB}.wal"
    "$BIN" "$BLOB_DB" -c "
        CREATE TABLE events_blob AS
        SELECT line::BLOB AS b
        FROM ${READ_CSV_SQL}
        WHERE length(line) > 0;
        CHECKPOINT;
    " >/dev/null 2>&1
}

RAW_ATTACH="ATTACH 'rawduck:${RAW_DB}' AS raw;"

W_RAW=$(time_best_of_3 write_rawduck)
W_JSON=$(time_best_of_3 write_json)
W_VARCHAR=$(time_best_of_3 write_varchar)
W_BLOB=$(time_best_of_3 write_blob)

# Row counts after write
RD=$("$BIN" -csv -c "${RAW_ATTACH} SELECT count(*) FROM raw.events;" 2>/dev/null | tail -1)
JK=$("$BIN" "$JSON_DB" -csv -c "SELECT count(*) FROM events_json;" 2>/dev/null | tail -1)
VS=$("$BIN" "$VARCHAR_DB" -csv -c "SELECT count(*) FROM events_varchar;" 2>/dev/null | tail -1)
BL=$("$BIN" "$BLOB_DB" -csv -c "SELECT count(*) FROM events_blob;" 2>/dev/null | tail -1)

if [[ "$RD" != "$ROWS" ]] || [[ "$JK" != "$ROWS" ]] || [[ "$VS" != "$ROWS" ]] || [[ "$BL" != "$ROWS" ]]; then
    echo "FAIL: row count mismatch rawduck=$RD json=$JK varchar=$VS blob=$BL (expected $ROWS)" | tee -a "$OUT"
    exit 1
fi
echo "PASS: all storage types wrote $ROWS rows" | tee -a "$OUT"

# Disk sizes (file on disk after CHECKPOINT)
D_RAW=$(file_bytes "$RAW_DB")
D_JSON=$(file_bytes "$JSON_DB")
D_VARCHAR=$(file_bytes "$VARCHAR_DB")
D_BLOB=$(file_bytes "$BLOB_DB")

{
    echo "storage,write_ms,disk_bytes"
    echo "rawduck,${W_RAW},${D_RAW}"
    echo "json,${W_JSON},${D_JSON}"
    echo "varchar,${W_VARCHAR},${D_VARCHAR}"
    echo "blob,${W_BLOB},${D_BLOB}"
} >"$WRITE_CSV"

{
    echo "storage,disk_bytes"
    echo "rawduck,${D_RAW}"
    echo "json,${D_JSON}"
    echo "varchar,${D_VARCHAR}"
    echo "blob,${D_BLOB}"
} >"$DISK_CSV"

# --- Read benchmarks ---
declare -a QUERY_IDS=(Q1 Q2 Q3 Q4)

declare -a RAW_Q=(
    "SELECT action, count(*) FROM raw.events GROUP BY action"
    "SELECT \"user.name\", count(*) AS n FROM raw.events WHERE action = 'click' GROUP BY 1 ORDER BY n DESC LIMIT 5"
    "SELECT sum(amount) FROM raw.events WHERE amount > 100"
    "SELECT count(DISTINCT \"user.plan\") FROM raw.events"
)

declare -a JSON_Q=(
    "SELECT json_extract_string(j, '\$.action'), count(*) FROM events_json GROUP BY 1"
    "SELECT json_extract_string(j, '\$.user.name'), count(*) FROM events_json WHERE json_extract_string(j, '\$.action') = 'click' GROUP BY 1 ORDER BY count(*) DESC LIMIT 5"
    "SELECT sum(CAST(json_extract(j, '\$.amount') AS DOUBLE)) FROM events_json WHERE CAST(json_extract(j, '\$.amount') AS DOUBLE) > 100"
    "SELECT count(DISTINCT json_extract_string(j, '\$.user.plan')) FROM events_json"
)

declare -a VARCHAR_Q=(
    "SELECT json_extract_string(s, '\$.action'), count(*) FROM events_varchar GROUP BY 1"
    "SELECT json_extract_string(s, '\$.user.name'), count(*) FROM events_varchar WHERE json_extract_string(s, '\$.action') = 'click' GROUP BY 1 ORDER BY count(*) DESC LIMIT 5"
    "SELECT sum(CAST(json_extract(s, '\$.amount') AS DOUBLE)) FROM events_varchar WHERE CAST(json_extract(s, '\$.amount') AS DOUBLE) > 100"
    "SELECT count(DISTINCT json_extract_string(s, '\$.user.plan')) FROM events_varchar"
)

declare -a BLOB_Q=(
    "SELECT json_extract_string(decode(b), '\$.action'), count(*) FROM events_blob GROUP BY 1"
    "SELECT json_extract_string(decode(b), '\$.user.name'), count(*) FROM events_blob WHERE json_extract_string(decode(b), '\$.action') = 'click' GROUP BY 1 ORDER BY count(*) DESC LIMIT 5"
    "SELECT sum(CAST(json_extract(decode(b), '\$.amount') AS DOUBLE)) FROM events_blob WHERE CAST(json_extract(decode(b), '\$.amount') AS DOUBLE) > 100"
    "SELECT count(DISTINCT json_extract_string(decode(b), '\$.user.plan')) FROM events_blob"
)

{
    echo "query_id,storage,ms"
    for i in "${!QUERY_IDS[@]}"; do
        id="${QUERY_IDS[$i]}"
        ms=$(bench_read_ms "" "$RAW_ATTACH" "${RAW_Q[$i]}")
        echo "${id},rawduck,${ms}"
        ms=$(bench_read_ms "$JSON_DB" "" "${JSON_Q[$i]}")
        echo "${id},json,${ms}"
        ms=$(bench_read_ms "$VARCHAR_DB" "" "${VARCHAR_Q[$i]}")
        echo "${id},varchar,${ms}"
        ms=$(bench_read_ms "$BLOB_DB" "" "${BLOB_Q[$i]}")
        echo "${id},blob,${ms}"
    done
} >"$READ_CSV"

# --- Render tables ---
{
    echo "RawDuck vs opaque storage — $(date -Iseconds)"
    echo "Rows: $ROWS | Source NDJSON: ${SOURCE_MB} MB"
    echo "Write CSV: $WRITE_CSV | Read CSV: $READ_CSV | Disk CSV: $DISK_CSV"
    echo ""

    print_table "Row counts (after write)" "
        SELECT * FROM (
            VALUES
                ('rawduck', ${RD}::BIGINT),
                ('json', ${JK}::BIGINT),
                ('varchar', ${VS}::BIGINT),
                ('blob', ${BL}::BIGINT)
        ) AS t(storage, rows);
    "

    print_table "Write speed — best of 3 runs" "
        WITH w AS (
            SELECT storage, write_ms, disk_bytes
            FROM read_csv('${WRITE_CSV}', header=true, auto_detect=true)
        )
        SELECT
            storage AS \"Storage\",
            write_ms AS \"Write (ms)\",
            round(${ROWS}::DOUBLE / (write_ms / 1000.0), 0) AS \"Rows/s\",
            round(${SOURCE_MB} / (write_ms / 1000.0), 2) AS \"MB/s\",
            disk_bytes AS \"On disk (bytes)\",
            round(disk_bytes::DOUBLE / 1048576.0, 2) AS \"On disk (MB)\"
        FROM w
        ORDER BY CASE storage
            WHEN 'rawduck' THEN 1 WHEN 'json' THEN 2 WHEN 'varchar' THEN 3 ELSE 4 END;
    "

    print_table "Read speed — best of 3 runs per query (ms)" "
        WITH labels AS (
            SELECT * FROM (
                VALUES
                    ('Q1', 'Q1: GROUP BY action'),
                    ('Q2', 'Q2: filter click, GROUP BY user.name'),
                    ('Q3', 'Q3: sum(amount) WHERE amount > 100'),
                    ('Q4', 'Q4: COUNT DISTINCT user.plan')
            ) AS t(query_id, query_label)
        ),
        times AS (
            SELECT query_id, storage, ms
            FROM read_csv('${READ_CSV}', header=true, auto_detect=true)
        )
        SELECT
            l.query_label AS \"Query\",
            max(CASE WHEN t.storage = 'rawduck' THEN t.ms END) AS \"RawDuck\",
            max(CASE WHEN t.storage = 'json' THEN t.ms END) AS \"JSON\",
            max(CASE WHEN t.storage = 'varchar' THEN t.ms END) AS \"VARCHAR\",
            max(CASE WHEN t.storage = 'blob' THEN t.ms END) AS \"BLOB\"
        FROM labels l
        JOIN times t ON l.query_id = t.query_id
        GROUP BY l.query_id, l.query_label
        ORDER BY l.query_id;
    "

    print_table "Read speed — average per storage (ms)" "
        SELECT
            storage AS \"Storage\",
            round(avg(ms), 1) AS \"Avg read (ms)\",
            min(ms) AS \"Best query (ms)\",
            max(ms) AS \"Worst query (ms)\"
        FROM read_csv('${READ_CSV}', header=true, auto_detect=true)
        GROUP BY storage
        ORDER BY CASE storage
            WHEN 'rawduck' THEN 1 WHEN 'json' THEN 2 WHEN 'varchar' THEN 3 ELSE 4 END;
    "

    print_table "Read speedup vs RawDuck (× slower, by query)" "
        WITH labels AS (
            SELECT * FROM (
                VALUES
                    ('Q1', 'Q1: GROUP BY action'),
                    ('Q2', 'Q2: filter click, GROUP BY user.name'),
                    ('Q3', 'Q3: sum(amount) WHERE amount > 100'),
                    ('Q4', 'Q4: COUNT DISTINCT user.plan')
            ) AS t(query_id, query_label)
        ),
        pivoted AS (
            SELECT
                query_id,
                max(CASE WHEN storage = 'rawduck' THEN ms END) AS rawduck_ms,
                max(CASE WHEN storage = 'json' THEN ms END) AS json_ms,
                max(CASE WHEN storage = 'varchar' THEN ms END) AS varchar_ms,
                max(CASE WHEN storage = 'blob' THEN ms END) AS blob_ms
            FROM read_csv('${READ_CSV}', header=true, auto_detect=true)
            GROUP BY query_id
        )
        SELECT
            l.query_label AS \"Query\",
            round(p.json_ms::DOUBLE / p.rawduck_ms, 2) AS \"JSON ×\",
            round(p.varchar_ms::DOUBLE / p.rawduck_ms, 2) AS \"VARCHAR ×\",
            round(p.blob_ms::DOUBLE / p.rawduck_ms, 2) AS \"BLOB ×\"
        FROM labels l
        JOIN pivoted p ON l.query_id = p.query_id
        ORDER BY l.query_id;
    "

    print_table "On-disk size" "
        WITH d AS (
            SELECT storage, disk_bytes
            FROM read_csv('${DISK_CSV}', header=true, auto_detect=true)
        ),
        base AS (SELECT disk_bytes AS raw_bytes FROM d WHERE storage = 'rawduck')
        SELECT
            d.storage AS \"Storage\",
            d.disk_bytes AS \"Bytes\",
            round(d.disk_bytes::DOUBLE / 1048576.0, 2) AS \"MB\",
            round(d.disk_bytes::DOUBLE / base.raw_bytes, 2) AS \"× vs RawDuck\"
        FROM d, base
        ORDER BY CASE d.storage
            WHEN 'rawduck' THEN 1 WHEN 'json' THEN 2 WHEN 'varchar' THEN 3 ELSE 4 END;
    "

    print_table "Summary — write, read, disk" "
        WITH w AS (
            SELECT storage, write_ms, disk_bytes
            FROM read_csv('${WRITE_CSV}', header=true, auto_detect=true)
        ),
        r AS (
            SELECT storage, round(avg(ms), 1) AS avg_read_ms
            FROM read_csv('${READ_CSV}', header=true, auto_detect=true)
            GROUP BY storage
        ),
        base AS (
            SELECT write_ms AS raw_write, disk_bytes AS raw_disk
            FROM w WHERE storage = 'rawduck'
        ),
        raw_read AS (
            SELECT avg_read_ms AS raw_read FROM r WHERE storage = 'rawduck'
        )
        SELECT
            w.storage AS \"Storage\",
            w.write_ms AS \"Write (ms)\",
            round(${ROWS}::DOUBLE / (w.write_ms / 1000.0), 0) AS \"Write rows/s\",
            r.avg_read_ms AS \"Read avg (ms)\",
            w.disk_bytes AS \"Disk (bytes)\",
            round(w.disk_bytes::DOUBLE / 1048576.0, 2) AS \"Disk (MB)\",
            round(w.write_ms::DOUBLE / base.raw_write, 2) AS \"Write ×\",
            round(r.avg_read_ms / raw_read.raw_read, 2) AS \"Read ×\",
            round(w.disk_bytes::DOUBLE / base.raw_disk, 2) AS \"Disk ×\"
        FROM w
        JOIN r ON w.storage = r.storage
        CROSS JOIN base
        CROSS JOIN raw_read
        ORDER BY CASE w.storage
            WHEN 'rawduck' THEN 1 WHEN 'json' THEN 2 WHEN 'varchar' THEN 3 ELSE 4 END;
    "
} | tee "$BENCH" | tee -a "$OUT"

echo "PASS: benchmark complete (see $BENCH)" | tee -a "$OUT"
