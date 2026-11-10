#!/bin/bash
# Regenerates docs/screenshot.png: the real macOS "Take a photo" prompt, an
# arrow, and the preview window showing the mock photo, at 2x with window
# shadows on a transparent background.
#
# Needs an iPhone set up for Continuity Camera (its camera opens and is
# cancelled again), ImageMagick, and Accessibility and Screen Recording access
# for the terminal (it presses Esc and captures windows).
set -euo pipefail
cd "$(dirname "$0")"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

xcrun swiftc -O ../iPhoneSnap.spoon/iphone-snap.swift -o "$tmp/iphone-snap"
xcrun swiftc -O screenshot-tools.swift -o "$tmp/screenshot-tools"

# The macOS prompt, cancelled with Esc once captured.
"$tmp/iphone-snap" > /dev/null &
pid=$!
read -r id _ < <("$tmp/screenshot-tools" find sheet)
sleep 0.8
screencapture -x -l"$id" "$tmp/prompt.png"
osascript -e 'tell application "System Events" to key code 53'
wait "$pid" || true

# The preview. A window capture leaves its translucent background flat gray,
# so the window's pixels come from a screen capture of the area around it,
# over a plain dark backdrop, cut to the window's shape and laid into the
# capture that has the shadow.
"$tmp/screenshot-tools" backdrop &
backdrop=$!
"$tmp/iphone-snap" --mock --default copy > /dev/null &
pid=$!
read -r id x y w h < <("$tmp/screenshot-tools" find preview)
sleep 0.8
margin=20
screencapture -x -l"$id" "$tmp/shadow.png"
screencapture -x -o -l"$id" "$tmp/window.png"
screencapture -x -R$((x - margin)),$((y - margin)),$((w + 2 * margin)),$((h + 2 * margin)) "$tmp/area.png"
kill -9 "$pid" "$backdrop"
wait "$pid" "$backdrop" 2> /dev/null || true

# Find the window in the screen capture by the photo's centre, which looks
# the same in both. It sits about 2 * margin pixels in, give or take a few.
read -r ww wh < <(magick identify -format '%w %h\n' "$tmp/window.png")
tx=$((ww / 2 - 150)) ty=$((wh / 2 - 50)) slack=16
magick "$tmp/window.png" -crop 300x100+$tx+$ty +repage "$tmp/template.png"
magick "$tmp/area.png" -crop $((300 + 2 * slack))x$((100 + 2 * slack))+$((tx + 2 * margin - slack))+$((ty + 2 * margin - slack)) +repage "$tmp/search.png"
# compare exits 1 whenever the images differ, which a search always reports.
match=$({ magick compare -metric RMSE -subimage-search "$tmp/search.png" "$tmp/template.png" null: 2>&1 || true; } |
  sed -nE 's/.*@ ([0-9]+),([0-9]+).*/\1 \2/p' | tail -1)
read -r dx dy <<< "$match"
magick "$tmp/area.png" -crop "${ww}x${wh}+$((2 * margin - slack + dx))+$((2 * margin - slack + dy))" +repage \
  \( "$tmp/window.png" -alpha extract \) -alpha off -compose CopyOpacity -composite "$tmp/body.png"
inset=$(magick "$tmp/shadow.png" -alpha extract -threshold 99% -format '%@' info: | sed -E 's/^[0-9]+x[0-9]+//')
magick "$tmp/shadow.png" "$tmp/body.png" -geometry "$inset" -compose over -composite "$tmp/preview.png"

"$tmp/screenshot-tools" arrow "$tmp/arrow.png"
# The shadows add about 112px of margin per side; -40 leaves ~72px between
# each window and the arrow.
magick -background none "$tmp/prompt.png" "$tmp/arrow.png" "$tmp/preview.png" -gravity center +smush -40 screenshot.png
echo "wrote $(pwd)/screenshot.png"
