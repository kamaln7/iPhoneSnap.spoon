#!/bin/bash
# Regenerates iPhoneSnap.spoon/docs.json from the docstrings and packs
# dist/iPhoneSnap.spoon.zip for a GitHub release, as SPOONS.md describes.
# Needs the hs command line tool: require("hs.ipc") in your Hammerspoon config.
#
# Publish with: gh release create vX.Y dist/iPhoneSnap.spoon.zip
set -euo pipefail
cd "$(dirname "$0")"

hs -c "hs.doc.builder.genJSON(\"$(pwd)/iPhoneSnap.spoon\")" | grep -v "^--" > iPhoneSnap.spoon/docs.json

mkdir -p dist
rm -f dist/*.spoon.zip
zip -qr dist/iPhoneSnap.spoon.zip iPhoneSnap.spoon -x 'iPhoneSnap.spoon/iphone-snap' 'iPhoneSnap.spoon/iphone-snap.sha256'
unzip -l dist/iPhoneSnap.spoon.zip
