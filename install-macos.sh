#!/usr/bin/env bash
# CreaBnB macOS installer (unsigned / ad-hoc). Run via:
#   curl -fsSL https://make-become.github.io/creabnb/install-macos.sh | bash
set -euo pipefail

REPO="${CREABNB_GITHUB_REPO:-make-become/creabnb}"
TAG="${CREABNB_RELEASE_TAG:-}"
DEST_DIR="${CREABNB_INSTALL_DIR:-}"
APP_NAME="CreaBnB.app"

arch="$(uname -m)"
case "$arch" in
  arm64) asset_arch="macos-arm64" ;;
  x86_64) asset_arch="macos-x64" ;;
  *)
    echo "Unsupported Mac architecture: $arch" >&2
    exit 1
    ;;
esac

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This installer is for macOS only." >&2
  exit 1
fi

if [[ -z "$DEST_DIR" ]]; then
  if [[ -w /Applications ]]; then
    DEST_DIR="/Applications"
  else
    DEST_DIR="$HOME/Applications"
  fi
fi

echo "→ Fetching release info from GitHub ($REPO)…"
api="https://api.github.com/repos/${REPO}/releases"
if [[ -n "$TAG" ]]; then
  json="$(curl -fsSL "${api}/tags/${TAG}")"
else
  json="$(curl -fsSL "${api}/latest")"
fi

tag="$(printf '%s' "$json" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("tag_name",""))' 2>/dev/null || true)"
if [[ -z "$tag" ]]; then
  tag="$(printf '%s' "$json" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)"
fi
if [[ -z "$tag" ]]; then
  echo "Could not resolve a release tag." >&2
  exit 1
fi

# Prefer zipped .app: creabnb-macos-arm64-v0.1.0.zip
zip_name="$(printf '%s' "$json" | python3 -c "
import json,sys,re
rel=json.load(sys.stdin)
pat=re.compile(r'creabnb-${asset_arch}-v.*\\.zip\$')
for a in rel.get('assets',[]):
  if pat.search(a.get('name','')):
    print(a['name']); break
" 2>/dev/null || true)"

if [[ -z "$zip_name" ]]; then
  zip_name="$(printf '%s' "$json" | sed -n "s/.*\"name\": *\"\\(creabnb-${asset_arch}-v[^\"]*\\.zip\\)\".*/\\1/p" | head -1)"
fi
if [[ -z "$zip_name" ]]; then
  echo "No ${asset_arch} zip asset found on release ${tag}." >&2
  echo "Open https://github.com/${REPO}/releases/tag/${tag}" >&2
  exit 1
fi

url="https://github.com/${REPO}/releases/download/${tag}/${zip_name}"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/creabnb-install.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

echo "→ Downloading ${zip_name} (${tag})…"
curl -fL --progress-bar -o "${tmp}/${zip_name}" "$url"

echo "→ Extracting…"
ditto -x -k "${tmp}/${zip_name}" "$tmp"
if [[ ! -d "${tmp}/${APP_NAME}" ]]; then
  echo "Zip did not contain ${APP_NAME}." >&2
  exit 1
fi

echo "→ Installing to ${DEST_DIR}/${APP_NAME}…"
mkdir -p "$DEST_DIR"
# Replace existing install
rm -rf "${DEST_DIR}/${APP_NAME}"
ditto "${tmp}/${APP_NAME}" "${DEST_DIR}/${APP_NAME}"

xattr -cr "${DEST_DIR}/${APP_NAME}" 2>/dev/null || true

echo "→ Installed in ${DEST_DIR}"
open "${DEST_DIR}/${APP_NAME}"
echo "Done."
