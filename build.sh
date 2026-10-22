#!/usr/bin/env bash
# build.sh — Build the iOS app in this repo and produce a Sideload-ready .ipa on this Ubuntu box.
#
# Discovers the product name, bundle ID and source folder from Vocabulary.xcodeproj
# so the same script works for any app in this repo, not just one specific project.
#
# What it does:
#   1. Sources the local ubuntu-ios toolchain (Swift 6.3.3 + private libplist/libimobiledevice).
#   2. Builds an unsigned device .app via xtool dev build.
#   3. Runs actool to compile Assets.xcassets into Assets.car and merge CFBundleIcons
#      + CFBundleDisplayName into the .app's Info.plist.
#   4. Packages the .app into releases/<Product>.ipa and a versioned timestamped copy.
#
# Usage:
#   ./build.sh                    # debug build, no ipa
#   ./build.sh --release --ipa    # release build, produce .ipa (default for sideloading)
#   ./build.sh --release --ipa --serve
#                                # build, then start a local HTTP server on port 8080
#                                  # so the iPhone can install via Safari + SideStore
#   ./build.sh --clean            # remove ./releases contents and ./build cache

set -euo pipefail

# --- paths -------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

IOS_ENV="$HOME/.local/bin/ios-env.sh"
SWIFT_LIB_DIR="$HOME/.local/swift-6.3.3/usr/lib/swift/linux"
SWIFT_GLIBC_DIR="$HOME/.local/swift-6.3.3/usr/lib/swift/linux/glibc/x86_64"

# Discover the Xcode project file (.xcodeproj) and the product name from it
XCODEPROJ_DIR="$(find "$SCRIPT_DIR" -maxdepth 2 -name '*.xcodeproj' -type d | head -1)"
[[ -n "$XCODEPROJ_DIR" ]] || fail "No .xcodeproj found in $SCRIPT_DIR"
PBXPROJ="$XCODEPROJ_DIR/project.pbxproj"
[[ -f "$PBXPROJ" ]] || fail "Missing $PBXPROJ"

# Product name = the first PBXNativeTarget name in the pbxproj
# (skip "Products" placeholder and the *Tests companion target)
PRODUCT="$(awk '
  /PBXNativeTarget section/   { in_section = 1; next }
  /End PBXNativeTarget section/ { in_section = 0; next }
  in_section && /name = / {
    gsub(/.*name = /, "")
    gsub(/;/, "")
    if ($0 != "" && $0 != "Products" && $0 !~ /Tests$/) {
      print; exit
    }
  }
' "$PBXPROJ")"
[[ -n "$PRODUCT" ]] || fail "Could not determine product name from $PBXPROJ"

BUILD_PKG_DIR="$SCRIPT_DIR/.build/linux-ios"
RELEASES_DIR="$SCRIPT_DIR/releases"
LOG_DIR="$SCRIPT_DIR/build/logs"
SERVE_PORT="${SERVE_PORT:-8080}"
ACT_TOOL="/home/baodoan/.swiftpm/swift-sdks/darwin.artifactbundle/Developer/Platforms/iPhoneOS.platform/Developer/usr/bin/actool"
IOS_SDK="/home/baodoan/.swiftpm/swift-sdks/darwin.artifactbundle/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS26.5.sdk"
ASSET_CATALOG="$SCRIPT_DIR/$PRODUCT/Assets.xcassets"

# --- defaults ----------------------------------------------------------------

CONFIGURATION="debug"
MAKE_IPA=0
SERVE=0
CLEAN=0
TRIPLE="arm64-apple-ios"

# --- args --------------------------------------------------------------------

usage() {
  sed -n '2,20p' "$0"
  exit 1
}

fail() { printf '\033[1;31m[build]\033[0m %s\n' "$*" >&2; exit 1; }
log()  { printf '\033[1;34m[build]\033[0m %s\n' "$*"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --release)        CONFIGURATION="release"; shift ;;
    --debug)          CONFIGURATION="debug"; shift ;;
    --ipa)            MAKE_IPA=1; shift ;;
    --serve)          SERVE=1; shift ;;
    --clean)          CLEAN=1; shift ;;
    --triple)         TRIPLE="$2"; shift 2 ;;
    -h|--help)        usage ;;
    *)                echo "Unknown argument: $1" >&2; usage ;;
  esac
done

# release + ipa is the practical default for sideloading
if [[ "$CONFIGURATION" == "debug" && "$MAKE_IPA" -eq 0 && "$CLEAN" -eq 0 ]]; then
  MAKE_IPA=1
fi

# --- subcommands -------------------------------------------------------------

if [[ "$CLEAN" -eq 1 ]]; then
  log "Cleaning $RELEASES_DIR (keeps the directory itself)"
  find "$RELEASES_DIR" -mindepth 1 -delete 2>/dev/null || true
  log "Cleaning $BUILD_PKG_DIR/xtool and $BUILD_PKG_DIR/.build"
  rm -rf "$BUILD_PKG_DIR/xtool" "$BUILD_PKG_DIR/.build"
  log "Done."
  exit 0
fi

# --- preflight ---------------------------------------------------------------

[[ -f "$IOS_ENV" ]] || fail "ios-env.sh not found at $IOS_ENV"
[[ -f "$BUILD_PKG_DIR/Package.swift" ]] || fail "$BUILD_PKG_DIR/Package.swift missing"
[[ -f "$BUILD_PKG_DIR/xtool.yml" ]] || fail "$BUILD_PKG_DIR/xtool.yml missing"
[[ -d "$SWIFT_LIB_DIR" ]] || fail "Swift runtime libs not found at $SWIFT_LIB_DIR"

# shellcheck disable=SC1090
source "$IOS_ENV"
export LD_LIBRARY_PATH="$SWIFT_LIB_DIR:${SWIFT_GLIBC_DIR:-}:$LD_LIBRARY_PATH"

command -v xtool >/dev/null 2>&1 || fail "xtool not on PATH after sourcing ios-env.sh"
command -v swift >/dev/null 2>&1 || fail "swift not on PATH after sourcing ios-env.sh"

mkdir -p "$RELEASES_DIR" "$LOG_DIR"

log "Product         : $PRODUCT"
log "Configuration   : $CONFIGURATION"
log "Triple          : $TRIPLE"
log "Output IPA      : $MAKE_IPA"
log "HTTP serve      : $SERVE"
log "Toolchain       : $(xtool --version 2>&1 | head -1)"
log "Swift           : $(swift --version 2>&1 | head -1)"

# --- build -------------------------------------------------------------------

GIT_SHA="$(git -C "$SCRIPT_DIR" rev-parse --short=7 HEAD 2>/dev/null || echo 'no-git')"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
APP_DIR="$BUILD_PKG_DIR/xtool/$PRODUCT.app"
PAYLOAD_DIR="$BUILD_PKG_DIR/xtool/Payload"
RAW_IPA="$BUILD_PKG_DIR/xtool/$PRODUCT.ipa"
VERSIONED_NAME="${PRODUCT}-${CONFIGURATION}-${GIT_SHA}-${TIMESTAMP}.ipa"
DEST_IPA="$RELEASES_DIR/$VERSIONED_NAME"
LATEST_IPA="$RELEASES_DIR/$PRODUCT.ipa"
LATEST_LINK="$RELEASES_DIR/latest"
BUILD_LOG="$LOG_DIR/build-${CONFIGURATION}-${TIMESTAMP}.log"

log "Building (this takes 60-180s on Linux) ..."
log "Log: $BUILD_LOG"

cd "$BUILD_PKG_DIR"
set +e
xtool dev build \
  --configuration "$CONFIGURATION" \
  --triple "$TRIPLE" \
  2>&1 | tee "$BUILD_LOG"
BUILD_RC=${PIPESTATUS[0]}
set -e

[[ "$BUILD_RC" -eq 0 ]] || fail "xtool build failed (rc=$BUILD_RC). See $BUILD_LOG."

[[ -d "$APP_DIR" ]] || fail "Expected .app at $APP_DIR after xtool build (none found)."

# --- compile asset catalog with actool --------------------------------------
# xtool on Linux copies the raw Assets.xcassets folder into the .app but
# does NOT run actool, so iOS sees the uncompiled catalog and shows a
# blank/generic app icon. Run actool ourselves to produce Assets.car and
# merge the resulting CFBundleIcons entries into Info.plist. Also force
# the lowercase display name (Xcode's GENERATE_INFOPLIST_FILE otherwise
# uses the product name and ignores INFOPLIST_KEY_CFBundleDisplayName).

if [[ -d "$ASSET_CATALOG" && -x "$ACT_TOOL" ]]; then
  COMPILED_DIR="$(mktemp -d)"
  PLIST_APPEND="$COMPILED_DIR/Info.plist.append"
  log "Compiling asset catalog: $ASSET_CATALOG"
  "$ACT_TOOL" \
    --platform iphoneos \
    --target-device iphone \
    --minimum-deployment-target 15.0 \
    --sdk "$IOS_SDK" \
    --app-icon AppIcon \
    --accent-color AccentColor \
    --output-partial-info-plist "$PLIST_APPEND" \
    --compile "$COMPILED_DIR" \
    "$ASSET_CATALOG" \
    2>"$LOG_DIR/actool-${TIMESTAMP}.log" || fail "actool failed; see $LOG_DIR/actool-${TIMESTAMP}.log"

  if [[ -f "$COMPILED_DIR/Assets.car" ]]; then
    cp -f "$COMPILED_DIR/Assets.car" "$APP_DIR/Assets.car"
    log "Copied Assets.car to $APP_DIR/Assets.car"

    python3 - <<PY
import plistlib
app_plist = plistlib.load(open("$APP_DIR/Info.plist", "rb"))
partial    = plistlib.load(open("$PLIST_APPEND", "rb"))
for k, v in partial.items():
    if k.startswith("CFBundleIcons"):
        app_plist[k] = v
# Force lowercase display name as defined in the project (INFOPLIST_KEY_CFBundleDisplayName)
app_plist["CFBundleDisplayName"] = "${PRODUCT,,}"
plistlib.dump(app_plist, open("$APP_DIR/Info.plist", "wb"), sort_keys=False)
print("[build] Merged", len(partial), "actool keys + lowercase display name into Info.plist")
PY
  else
    log "WARN: actool produced no Assets.car; icon not applied"
  fi
  rm -rf "$COMPILED_DIR"
fi

# --- package the IPA ourselves ---------------------------------------------
# Now that actool has injected Assets.car + CFBundleIcons into the .app,
# create a Payload/<Product>.app directory and zip it into the .ipa.

if [[ "$MAKE_IPA" -eq 1 ]]; then
  rm -rf "$PAYLOAD_DIR"
  mkdir -p "$PAYLOAD_DIR"
  cp -R "$APP_DIR" "$PAYLOAD_DIR/$PRODUCT.app"
  rm -f "$RAW_IPA"
  (cd "$PAYLOAD_DIR/.." && zip -qr "$RAW_IPA" Payload)
  log "Packaged IPA: $RAW_IPA"

  # Stage to ./releases/
  cp -v "$RAW_IPA" "$DEST_IPA"
  cp -f  "$DEST_IPA" "$LATEST_IPA"
  ln -sfn "$VERSIONED_NAME" "$LATEST_LINK"

  # Prune anything older than the last 10 builds to keep the folder tidy
  ls -1t "$RELEASES_DIR"/${PRODUCT}-*.ipa 2>/dev/null \
    | tail -n +11 \
    | xargs -r rm -f
fi

# --- inspect -----------------------------------------------------------------

PLIST="$APP_DIR/Info.plist"
if [[ -f "$PLIST" ]]; then
  MIN_IOS=$(python3 -c "import plistlib; p=plistlib.load(open('$PLIST','rb')); print(p.get('MinimumOSVersion','?'))" 2>/dev/null || echo '?')
  BUNDLE_ID=$(python3 -c "import plistlib; p=plistlib.load(open('$PLIST','rb')); print(p.get('CFBundleIdentifier','?'))" 2>/dev/null || echo '?')
  DISPLAY=$(python3 -c "import plistlib; p=plistlib.load(open('$PLIST','rb')); print(p.get('CFBundleDisplayName','?'))" 2>/dev/null || echo '?')
  log "Bundle ID       : $BUNDLE_ID"
  log "Display name    : $DISPLAY"
  log "MinimumOSVersion: $MIN_IOS"
fi

# --- optional serve ----------------------------------------------------------

if [[ "$SERVE" -eq 1 && "$MAKE_IPA" -eq 1 ]]; then
  HOST_IP="$(hostname -I | awk '{print $1}')"
  URL="http://${HOST_IP}:${SERVE_PORT}/${PRODUCT}.ipa"
  SIDESTORE_URL="sidestore://install?url=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${URL}', safe=''))")"
  log "HTTP server starting on port $SERVE_PORT, serving $RELEASES_DIR/"
  log "Install on iPhone (Safari):"
  log "  ${URL}"
  log "  -> Share -> Open in SideStore"
  log "Or open the SideStore URL directly:"
  log "  ${SIDESTORE_URL}"
  cd "$RELEASES_DIR"
  exec python3 -m http.server "$SERVE_PORT" --bind 0.0.0.0
fi

# --- summary -----------------------------------------------------------------

log "Build complete."
if [[ "$MAKE_IPA" -eq 1 ]]; then
  log "IPA        : $DEST_IPA ($(du -h "$DEST_IPA" | awk '{print $1}'))"
  log "Latest sym : $LATEST_IPA"
  log "Versioned  : $LATEST_LINK -> $VERSIONED_NAME"
fi
log "Log        : $BUILD_LOG"
log "Next       :"
log "  - Local:  ./build.sh --release --ipa --serve"
log "  - CI:     git push origin main (the .github workflow publishes the same artifact)"
