#!/bin/sh
# Makes the README screenshots with tools/koreader/render_screens.lua: English in docs/screenshots and
# Portuguese in docs/screenshots/pt. Usage: KOREADER_DIR=<desktop KOReader> tools/koreader/readme_screens.sh
set -eu
plugin="$(cd "$(dirname "$0")/../.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
# README name, then the render_screens.lua picture it comes from.
pictures="commander:08_magic_commander_4p two_players:07_magic_2p pokemon:12_pokemon_2p checkup:14_pokemon_checkup_flipped
home:01_home_saved layouts:05_layouts seats:06_seats dice:22_magic_dice_3d6"
for lang in en pt; do
    mkdir -p "$work/$lang"
    LANG_CODE="$lang" OUTPUT_DIR="$work/$lang" sh "$plugin/tools/koreader/run_headless.sh" "$plugin/tools/koreader/render_screens.lua"
    out="$plugin/docs/screenshots"
    [ "$lang" = en ] || out="$out/$lang"
    mkdir -p "$out"
    for item in $pictures; do
        cp "$work/$lang/${item#*:}.png" "$out/${item%%:*}.png"
    done
done
echo "Screenshots saved in docs/screenshots and docs/screenshots/pt"
