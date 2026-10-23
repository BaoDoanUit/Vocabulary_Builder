#!/usr/bin/env bash
# Verify the import -> library flow against the live server.
#
#   tools/livecheck/run.sh [base-url]
#
# Copies the app's Foundation-only sources into this package, patches the
# two Apple-only imports, then runs the check. Nothing in the app itself
# is modified.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
BASE_URL="${1:-http://bao-thinkcentre-m93p.tail2c53fc.ts.net:2001}"
OUT="$HERE/.build"

echo "[livecheck] source   : $REPO"
echo "[livecheck] base url : $BASE_URL"

rm -rf "$OUT"
mkdir -p "$OUT/Sources/VocabularyBuilder" "$OUT/Sources/LiveCheck" "$OUT/Shims/Combine"

cp "$HERE/Package.swift"            "$OUT/Package.swift"
cp "$HERE/Shims/Combine/Combine.swift" "$OUT/Shims/Combine/"
cp "$HERE/Sources/LiveCheck/main.swift" "$OUT/Sources/LiveCheck/"

for f in Core/APIModels.swift Core/APIError.swift Core/APIClientProtocol.swift \
         Core/APIClient.swift Core/AppSettings.swift \
         Stores/LibraryStore.swift Stores/SessionStore.swift; do
  cp "$REPO/VocabularyBuilder/$f" "$OUT/Sources/VocabularyBuilder/$(basename "$f")"
done

# `URLSession` lives in FoundationNetworking on Linux, and
# `waitsForConnectivity` is read-only there.
sed -i 's/^import Foundation$/import Foundation\nimport Combine\n#if canImport(FoundationNetworking)\nimport FoundationNetworking\n#endif/' "$OUT/Sources/VocabularyBuilder/APIClient.swift"
sed -i 's/^        config.waitsForConnectivity = true$/        #if !canImport(FoundationNetworking)\n        config.waitsForConnectivity = true\n        #endif/' "$OUT/Sources/VocabularyBuilder/APIClient.swift"
# The check compiles into the same module, so it must not import it.
sed -i '/^import VocabularyBuilder$/d' "$OUT/Sources/LiveCheck/main.swift"
sed -i "s|^let base = URL(string: .*|let base = URL(string: \"$BASE_URL\")!|" "$OUT/Sources/LiveCheck/main.swift"

cd "$OUT"
swift run LiveCheck
