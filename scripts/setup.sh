#!/usr/bin/env bash
# Download and install RawDuck v0.0.2 (DuckDB 1.5.3) into ./bin
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN_DIR="$ROOT/bin"
VERSION="v0.0.2"
TMP="$ROOT/.cache"

mkdir -p "$BIN_DIR" "$TMP"

detect_archive() {
    local os arch
    os="$(uname -s | tr '[:upper:]' '[:lower:]')"
    arch="$(uname -m)"
    case "$os-$arch" in
        linux-x86_64|linux-amd64) echo "rawduck-linux-amd64-${VERSION}.tar.gz" ;;
        linux-aarch64|linux-arm64)  echo "rawduck-linux-arm64-${VERSION}.tar.gz" ;;
        darwin-arm64)               echo "rawduck-macos-arm64-${VERSION}.tar.gz" ;;
        darwin-x86_64)              echo "rawduck-macos-amd64-${VERSION}.tar.gz" ;;
        *) echo "Unsupported platform: $os $arch — install RawDuck manually into bin/" >&2; exit 1 ;;
    esac
}

ARCHIVE="$(detect_archive)"
URL="https://github.com/quackscience/rawduck/releases/download/${VERSION}/${ARCHIVE}"
SRC_DIR="$TMP/${ARCHIVE%.tar.gz}"

if [[ -x "$BIN_DIR/rawduck" ]]; then
    echo "Already installed: $BIN_DIR/rawduck"
    "$BIN_DIR/rawduck" --version
    exit 0
fi

echo "Downloading RawDuck ${VERSION} (${ARCHIVE})..."
curl -fsSL "$URL" -o "$TMP/$ARCHIVE"

echo "Extracting..."
tar -xzf "$TMP/$ARCHIVE" -C "$TMP"

cp "$SRC_DIR/rawduck" "$BIN_DIR/rawduck"
cp "$SRC_DIR/duckdb" "$BIN_DIR/duckdb"
mkdir -p "$BIN_DIR/extension/rawduck"
cp "$SRC_DIR/extension/rawduck/rawduck.duckdb_extension" "$BIN_DIR/extension/rawduck/"
chmod +x "$BIN_DIR/rawduck" "$BIN_DIR/duckdb"

echo "Installed:"
"$BIN_DIR/rawduck" --version
echo "Binary: $BIN_DIR/rawduck"
