#!/usr/bin/env bash
# Keeps every screen on the design tokens and parts in App/Main/Theme (see CONTRIBUTING.md,
# "Design system"). Outside that folder a view may not write a font size, a neutral color, a
# corner radius or a spacing as a number: it names a token (TextSize, Ink, Radius, Space) or uses
# a part. 0 and 1 are allowed (no space, a hairline). Drawing code that paints pixels with AppKit
# (the menu bar renderer, capture overlays) is not SwiftUI layout and is not checked.
#
#   scripts/lint-design.sh        prints every offending line, exits 1 if there is one
set -euo pipefail
cd "$(dirname "$0")/.."

rules=(
  'font size outside the text roles (use .font(.role(...)) or .textRole(...))|\.system\(size:|NSFont\.systemFont\(ofSize'
  'color as a number|Color\.white\.opacity\(|Color\.black\.opacity\(|(^|[^S])Color\((red|white):'
  'corner radius as a number|cornerRadius: *[0-9]'
  'spacing as a number|spacing: *([2-9]|[1-9][0-9])'
  'spacer length as a number|minLength: *([2-9]|[1-9][0-9])'
  'padding as a number|\.padding\([^)]*(\b|, )([2-9]|[1-9][0-9])(\.[0-9]+)?\)'
  'control size outside the parts|\.controlSize\('
  'a control drawn outside the parts (use RowSwitch, LabeledSwitch, RowMenu, PickerRow, Segmented)|(^|[^A-Za-z])(Toggle|Picker)\('
  'a system color where a palette color exists (Tile, Brand, Status, Ink)|color: *\.(blue|green|red|orange|yellow|pink|purple|mint|teal|cyan|indigo|gray)\b|Color\.(blue|green|red|orange|yellow|pink|purple|mint|teal|cyan|indigo|gray)\b'
  'a color made transparent by hand (use Tint, Shade, Fill, Line)|(Brand|Ink|Status|Tile|Surface|MonitorStyle|GuideInk)\.[a-zA-Z]+\.opacity\(0\.|\.(black|white|primary|color)\.opacity\(0\.|[^A-Za-z](color|tint)\.opacity\(0\.'
  'a system color where a token exists|(foregroundStyle|foregroundColor|fill|background|stroke|strokeBorder)\(\.(orange|red|yellow|green|blue|purple|pink|mint|teal|cyan|indigo|secondary|tertiary|primary)\b'
)

# Code that paints pixels with AppKit, or draws the user's own content (annotation text and colors),
# chooses its sizes and colors for that drawing and is not checked.
pixel_drawing='MenuBar/MenuBarRenderer.swift|Capture/AnnotationRenderer.swift|Capture/AnnotationDemo.swift|Capture/SelectionOverlay.swift'
files=$(find App/Main -name '*.swift' -not -path 'App/Main/Theme/*' | grep -vE "$pixel_drawing")
status=0
for rule in "${rules[@]}"; do
  name="${rule%%|*}"
  pattern="${rule#*|}"
  # shellcheck disable=SC2086
  if hits=$(grep -nE "$pattern" $files); then
    echo "design lint: $name"
    echo "$hits" | sed 's/^/  /'
    status=1
  fi
done
exit $status
