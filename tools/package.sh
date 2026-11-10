#!/bin/sh
# Builds the plugin zip in dist/, with its checksum.
set -eu
cd "$(dirname "$0")/.."
name=matkeeper.koplugin
for file in LICENSE NOTICE data/i18n.lua assets/art/banner.png assets/logos/magic_large.png assets/logos/pokemon_large.png assets/screensaver.png; do
    if [ ! -f "$file" ]; then
        echo "$file not found: the package cannot be built without it." >&2
        exit 1
    fi
done
rm -rf dist
stage="dist/stage/$name"
mkdir -p "$stage/data"
cp -R _meta.lua main.lua LICENSE NOTICE matkeeper assets "$stage/"
cp data/i18n.lua "$stage/data/"
find dist/stage \( -name '._*' -o -name '.DS_Store' \) -delete
(cd dist/stage && zip -qrX "../$name.zip" "$name")
rm -rf dist/stage
(cd dist && shasum -a 256 "$name.zip" > "$name.zip.sha256")
echo "Package built: dist/$name.zip"
