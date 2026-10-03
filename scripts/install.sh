#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP_SOURCE="$PWD/dist/Halo.app"
APP_PARENT="$HOME/Applications"
APP_DEST="$APP_PARENT/Halo.app"
EXPECTED_ID="dev.kevin.halo"
STAGING_DIR=""
BACKUP_DIR=""
PUBLISHED=false

bundle_id() {
  /usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$1/Contents/Info.plist"
}

cleanup() {
  local status=$?
  set +e
  trap - EXIT
  if [[ "$status" -ne 0 && -n "$BACKUP_DIR" && -d "$BACKUP_DIR/Halo.app" ]]; then
    if [[ "$PUBLISHED" == true ]]; then
      rm -rf "$APP_DEST"
    fi
    if [[ ! -e "$APP_DEST" && ! -L "$APP_DEST" ]]; then
      if mv "$BACKUP_DIR/Halo.app" "$APP_DEST"; then
        echo "Installation failed; restored the previous Halo.app." >&2
      else
        echo "Could not restore Halo.app; the previous app is at $BACKUP_DIR/Halo.app." >&2
      fi
    else
      echo "Installation failed; the previous app is preserved at $BACKUP_DIR/Halo.app." >&2
    fi
  elif [[ "$status" -ne 0 && "$PUBLISHED" == true ]]; then
    rm -rf "$APP_DEST"
  fi
  if [[ -n "$STAGING_DIR" ]]; then
    rm -rf "$STAGING_DIR"
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Reject missing, incorrect, or invalid source bundles before touching an installation.
if [[ ! -d "$APP_SOURCE" || "$(bundle_id "$APP_SOURCE")" != "$EXPECTED_ID" ]]; then
  echo "The source must be a built dev.kevin.halo bundle: $APP_SOURCE" >&2
  exit 1
fi
codesign --verify --deep --strict "$APP_SOURCE"

mkdir -p "$APP_PARENT"
STAGING_DIR=$(mktemp -d "$APP_PARENT/.Halo-install.XXXXXX")
ditto "$APP_SOURCE" "$STAGING_DIR/Halo.app"
if [[ "$(bundle_id "$STAGING_DIR/Halo.app")" != "$EXPECTED_ID" ]]; then
  echo "The staged app has an unexpected bundle identifier." >&2
  exit 1
fi
codesign --verify --deep --strict "$STAGING_DIR/Halo.app"

# Check immediately before replacement; never follow or overwrite a destination symlink.
if [[ -e "$APP_DEST" || -L "$APP_DEST" ]]; then
  if [[ -L "$APP_DEST" || "$(bundle_id "$APP_DEST")" != "$EXPECTED_ID" ]]; then
    echo "Another app already exists at $APP_DEST. It has not been changed." >&2
    exit 1
  fi
  BACKUP_DIR=$(mktemp -d "$APP_PARENT/.Halo-backup.XXXXXX")
  mv "$APP_DEST" "$BACKUP_DIR/Halo.app"
fi
mv "$STAGING_DIR/Halo.app" "$APP_DEST"
PUBLISHED=true
codesign --verify --deep --strict "$APP_DEST"
echo "Installed: $APP_DEST"
if [[ -n "$BACKUP_DIR" ]]; then
  echo "Previous app preserved: $BACKUP_DIR/Halo.app"
fi
