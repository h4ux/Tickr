#!/bin/bash
# Generates app icon PNGs from an SVG source using macOS sips
# Requires: Python 3 (for the SVG generator) or provide your own icon_1024.png

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ICON_DIR="$PROJECT_DIR/Tickr/Assets.xcassets/AppIcon.appiconset"

# Generate a stock chart SVG icon using Python
python3 - << 'PYTHON_SCRIPT'
import subprocess, os

svg = '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="bg" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" style="stop-color:#1a1a2e"/>
      <stop offset="100%" style="stop-color:#16213e"/>
    </linearGradient>
    <linearGradient id="greenGlow" x1="0%" y1="100%" x2="0%" y2="0%">
      <stop offset="0%" style="stop-color:#00b894;stop-opacity:0.1"/>
      <stop offset="100%" style="stop-color:#00b894;stop-opacity:0.4"/>
    </linearGradient>
  </defs>
  <!-- Background rounded rect -->
  <rect width="1024" height="1024" rx="220" fill="url(#bg)"/>
  <!-- Glow area under chart -->
  <path d="M180,700 L300,580 L440,620 L560,420 L700,350 L844,250 L844,700 Z" fill="url(#greenGlow)"/>
  <!-- Stock chart line -->
  <polyline points="180,700 300,580 440,620 560,420 700,350 844,250"
    fill="none" stroke="#00d2a0" stroke-width="36" stroke-linecap="round" stroke-linejoin="round"/>
  <!-- Arrow tip -->
  <polygon points="844,250 790,310 830,320" fill="#00d2a0"/>
  <!-- Dollar sign -->
  <text x="512" y="900" text-anchor="middle" font-family="SF Pro Display,Helvetica Neue,Arial" font-size="140" font-weight="700" fill="#00d2a080">$</text>
</svg>'''

script_dir = os.path.dirname(os.path.abspath(__file__)) if '__file__' in dir() else os.getcwd()
project_dir = os.environ.get('PROJECT_DIR', os.path.dirname(script_dir))
svg_path = os.path.join(project_dir, 'scripts', 'icon.svg')

with open(svg_path, 'w') as f:
    f.write(svg)
print(f"SVG written to {svg_path}")
PYTHON_SCRIPT

SVG_PATH="$SCRIPT_DIR/icon.svg"

# Check if we can convert SVG to PNG
# Try using qlmanage (built into macOS) or rsvg-convert if available
convert_svg() {
    local size=$1
    local output="$ICON_DIR/icon_${size}.png"

    if command -v rsvg-convert &>/dev/null; then
        rsvg-convert -w "$size" -h "$size" "$SVG_PATH" -o "$output"
    elif command -v magick &>/dev/null; then
        magick -background none -density 300 -resize "${size}x${size}" "$SVG_PATH" "$output"
    elif command -v convert &>/dev/null; then
        convert -background none -density 300 -resize "${size}x${size}" "$SVG_PATH" "$output"
    else
        # Fallback: use qlmanage to render then sips to resize
        # First render at max size
        if [ ! -f "$ICON_DIR/icon_1024.png" ]; then
            echo "No SVG converter found. Please install librsvg (brew install librsvg) or ImageMagick."
            echo "Alternatively, place a 1024x1024 PNG at: $ICON_DIR/icon_1024.png"
            echo "Then re-run this script to generate other sizes."
            exit 1
        fi
        sips -z "$size" "$size" "$ICON_DIR/icon_1024.png" --out "$output" >/dev/null 2>&1
    fi
    echo "Generated: icon_${size}.png"
}

# Generate all required sizes
SIZES=(16 32 64 128 256 512 1024)

# If we have a converter, generate from SVG
if command -v rsvg-convert &>/dev/null || command -v magick &>/dev/null || command -v convert &>/dev/null; then
    for size in "${SIZES[@]}"; do
        convert_svg "$size"
    done
    echo "All icons generated from SVG."
elif [ -f "$ICON_DIR/icon_1024.png" ]; then
    # Generate from existing 1024 PNG
    for size in "${SIZES[@]}"; do
        if [ "$size" -ne 1024 ]; then
            sips -z "$size" "$size" "$ICON_DIR/icon_1024.png" --out "$ICON_DIR/icon_${size}.png" >/dev/null 2>&1
            echo "Generated: icon_${size}.png"
        fi
    done
    echo "All icons generated from icon_1024.png."
else
    echo "ERROR: No SVG converter found and no icon_1024.png exists."
    echo "Install librsvg: brew install librsvg"
    echo "Or place a 1024x1024 PNG at: $ICON_DIR/icon_1024.png"
    exit 1
fi

echo "Done! Icons are in: $ICON_DIR"
