#!/usr/bin/env bash
# Restructure the vendored CsoundLib64.framework into a STRUCTURALLY VALID,
# codesign-able, embeddable macOS framework.
#
# WHY THIS IS NEEDED
# ------------------
# Csound's official macOS CsoundLib64.framework is laid out for loose loading from
# /Library/Frameworks: it puts a REAL `libs/` directory (libsndfile + audio codecs)
# at the framework ROOT, and the main binary loads them via
#   @loader_path/../../libs/libsndfile.1.dylib
# A valid macOS framework must have ONLY symlinks at its root; all real files live
# under Versions/. The root `libs/` dir = "unsealed contents" → codesign cannot seal
# it as an embedded framework, and the adhoc-signed (TeamIdentifier=not set) dylibs
# fail hardened-runtime library validation → the app crashes at launch.
#
# THE FIX (idempotent, reproducible)
# ----------------------------------
#   1. Move the real `libs/` dir to Versions/6.0/libs (so root holds only symlinks).
#   2. Repoint the main binary's single dependency:
#        @loader_path/../../libs/libsndfile.1.dylib  ->  @loader_path/libs/libsndfile.1.dylib
#      (loader is Versions/6.0/CsoundLib64, so @loader_path/libs == Versions/6.0/libs.)
#      The codec dylibs reference each other via @loader_path/<name> (same dir), so
#      moving them together preserves all cross-references — nothing else to repoint.
#   3. Add a root `libs -> Versions/Current/libs` symlink for any consumer that still
#      expects ../../libs from the root symlink position (belt & suspenders; harmless).
#
# After this, Xcode's "Embed & Sign" re-signs the framework AND its nested dylibs
# with your team identity → Team IDs match → library validation passes. The brittle
# per-build re-sign run-script phase is no longer needed and should be removed.
#
# Run from the Etherpad-iOS directory (or anywhere; path is resolved below).
set -euo pipefail

FW="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/CsoundLib64.framework"
echo "Framework: $FW"
[ -d "$FW" ] || { echo "ERROR: framework not found"; exit 1; }

VERS="$FW/Versions/6.0"
BIN="$VERS/CsoundLib64"

# --- Step 1: relocate real libs/ under Versions/6.0 (idempotent) -------------
if [ -d "$FW/libs" ] && [ ! -L "$FW/libs" ]; then
  echo "Moving real libs/ -> Versions/6.0/libs"
  rm -rf "$VERS/libs"
  mv "$FW/libs" "$VERS/libs"
elif [ -d "$VERS/libs" ]; then
  echo "libs/ already under Versions/6.0 — skipping move"
else
  echo "ERROR: no libs/ directory found at root or under Versions"; exit 1
fi

# --- Step 2: repoint the main binary's libsndfile dependency -----------------
OLD="@loader_path/../../libs/libsndfile.1.dylib"
NEW="@loader_path/libs/libsndfile.1.dylib"
if otool -L "$BIN" | grep -q "$OLD"; then
  echo "Repointing main binary: $OLD -> $NEW"
  install_name_tool -change "$OLD" "$NEW" "$BIN"
else
  echo "Main binary already repointed — skipping"
fi

# --- Step 3: root symlink for libs (belt & suspenders) ----------------------
if [ ! -e "$FW/libs" ]; then
  ln -s "Versions/Current/libs" "$FW/libs"
  echo "Added root symlink libs -> Versions/Current/libs"
fi

# --- Step 4: strip stale adhoc signatures so Xcode re-signs cleanly ----------
# (Embed & Sign will re-sign with your team; removing the adhoc/codesign dirs
#  avoids "resource fork / Finder info" and seal conflicts.)
echo "Stripping stale signatures (Xcode Embed & Sign will re-sign with your team)"
find "$VERS/libs" -name '*.dylib' -exec codesign --remove-signature {} + 2>/dev/null || true
codesign --remove-signature "$BIN" 2>/dev/null || true
rm -rf "$VERS/_CodeSignature"

echo
echo "Verifying structure:"
echo "  root entries (should be symlinks + Versions only):"
ls -la "$FW" | awk '{print "    "$0}'
echo "  main binary libsndfile dep:"
otool -L "$BIN" | grep libsndfile | awk '{print "    "$0}'
echo
echo "DONE. Now in Xcode: ensure CsoundLib64.framework is 'Embed & Sign' in the"
echo "macOS target, and REMOVE the manual re-sign Run Script build phase."
