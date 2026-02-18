#!/usr/bin/env sh
set -eu

REPO="${ZPM_UPDATE_REPO:-crnobog69/zpm-bin}"
INSTALL_DIR="${ZPM_INSTALL_DIR:-$HOME/.local/bin}"
APP_NAME="zpm"

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 1
  fi
}

need_cmd curl
need_cmd uname
need_cmd mktemp
need_cmd grep
need_cmd awk
need_cmd tr

if command -v sha256sum >/dev/null 2>&1; then
  HASH_CMD="sha256sum"
elif command -v shasum >/dev/null 2>&1; then
  HASH_CMD="shasum -a 256"
else
  echo "missing sha256 tool (sha256sum or shasum)" >&2
  exit 1
fi

OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH_RAW="$(uname -m)"

case "$OS" in
  linux) OS="linux" ;;
  *)
    echo "unsupported OS: $OS (supported: linux)" >&2
    exit 1
    ;;
esac

case "$ARCH_RAW" in
  x86_64|amd64) ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *)
    echo "unsupported architecture: $ARCH_RAW" >&2
    exit 1
    ;;
esac

API_URL="https://api.github.com/repos/$REPO/releases/latest"
TAG="$(curl -fsSL "$API_URL" | awk -F'"' '/"tag_name":/ { print $4; exit }')"
if [ -z "$TAG" ]; then
  echo "failed to resolve latest tag from $API_URL" >&2
  exit 1
fi

ASSET="$APP_NAME-$OS-$ARCH"
ASSET_URL="https://github.com/$REPO/releases/download/$TAG/$ASSET"
CHECKSUMS_URL="https://github.com/$REPO/releases/download/$TAG/checksums.txt"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT INT TERM
TMP_ASSET="$TMPDIR/$ASSET"
TMP_CHECKSUMS="$TMPDIR/checksums.txt"

echo "downloading $ASSET_URL"
curl -fL "$ASSET_URL" -o "$TMP_ASSET"
curl -fL "$CHECKSUMS_URL" -o "$TMP_CHECKSUMS"

EXPECTED="$(grep "  $ASSET\$" "$TMP_CHECKSUMS" | awk '{print $1}' | head -n1 | tr '[:upper:]' '[:lower:]')"
if [ -z "$EXPECTED" ]; then
  EXPECTED="$(grep " $ASSET\$" "$TMP_CHECKSUMS" | awk '{print $1}' | head -n1 | tr '[:upper:]' '[:lower:]')"
fi
EXPECTED="${EXPECTED#sha256:}"
if [ -z "$EXPECTED" ]; then
  echo "missing checksum for $ASSET in checksums.txt" >&2
  exit 1
fi

ACTUAL="$(sh -c "$HASH_CMD \"$TMP_ASSET\"" | awk '{print $1}' | tr '[:upper:]' '[:lower:]')"
if [ "$ACTUAL" != "$EXPECTED" ]; then
  echo "checksum mismatch for $ASSET" >&2
  echo "expected: $EXPECTED" >&2
  echo "actual:   $ACTUAL" >&2
  exit 1
fi

mkdir -p "$INSTALL_DIR"
install -m 0755 "$TMP_ASSET" "$INSTALL_DIR/$APP_NAME"

echo "$APP_NAME installed to $INSTALL_DIR/$APP_NAME ($TAG)"
echo "if needed, add to PATH: export PATH=\"$INSTALL_DIR:\$PATH\""
