#!/usr/bin/env sh
# Fetch drift's web worker + sqlite3 wasm into web/ for a manual `flutter build
# web` (the Nix build fetches them itself). Versions match pubspec.lock.
set -eu
cd "$(dirname "$0")/../.."
curl -fsSL -o web/drift_worker.js \
  https://github.com/simolus3/drift/releases/download/drift-2.34.0/drift_worker.js
curl -fsSL -o web/sqlite3.wasm \
  https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-3.3.3/sqlite3.wasm
echo "Fetched web/drift_worker.js and web/sqlite3.wasm"
