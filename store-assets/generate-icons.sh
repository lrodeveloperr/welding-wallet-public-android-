#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ICON_SVG="$ROOT_DIR/store-assets/app-icon.svg"
FEATURE_SVG="$ROOT_DIR/store-assets/feature-graphic.svg"
IOS_DIR="$ROOT_DIR/ios/Runner/Assets.xcassets/AppIcon.appiconset"
ANDROID_RES="$ROOT_DIR/android/app/src/main/res"
PLAY_DIR="$ROOT_DIR/store-assets/google-play"

render() {
  local size="$1"
  local output="$2"
  inkscape "$ICON_SVG" --export-type=png --export-filename="$output" --export-width="$size" --export-height="$size" >/dev/null
  convert "$output" -alpha off -strip "$output"
}

render 1024 "$IOS_DIR/Icon-App-1024x1024@1x.png"
render 20 "$IOS_DIR/Icon-App-20x20@1x.png"
render 40 "$IOS_DIR/Icon-App-20x20@2x.png"
render 60 "$IOS_DIR/Icon-App-20x20@3x.png"
render 29 "$IOS_DIR/Icon-App-29x29@1x.png"
render 58 "$IOS_DIR/Icon-App-29x29@2x.png"
render 87 "$IOS_DIR/Icon-App-29x29@3x.png"
render 40 "$IOS_DIR/Icon-App-40x40@1x.png"
render 80 "$IOS_DIR/Icon-App-40x40@2x.png"
render 120 "$IOS_DIR/Icon-App-40x40@3x.png"
render 120 "$IOS_DIR/Icon-App-60x60@2x.png"
render 180 "$IOS_DIR/Icon-App-60x60@3x.png"
render 76 "$IOS_DIR/Icon-App-76x76@1x.png"
render 152 "$IOS_DIR/Icon-App-76x76@2x.png"
render 167 "$IOS_DIR/Icon-App-83.5x83.5@2x.png"

render 48 "$ANDROID_RES/mipmap-mdpi/ic_launcher.png"
render 72 "$ANDROID_RES/mipmap-hdpi/ic_launcher.png"
render 96 "$ANDROID_RES/mipmap-xhdpi/ic_launcher.png"
render 144 "$ANDROID_RES/mipmap-xxhdpi/ic_launcher.png"
render 192 "$ANDROID_RES/mipmap-xxxhdpi/ic_launcher.png"

render 512 "$PLAY_DIR/icon-512.png"
inkscape "$FEATURE_SVG" --export-type=png --export-filename="$PLAY_DIR/feature-graphic-1024x500.png" --export-width=1024 --export-height=500 >/dev/null
convert "$PLAY_DIR/feature-graphic-1024x500.png" -alpha off -strip "$PLAY_DIR/feature-graphic-1024x500.png"

identify "$PLAY_DIR/icon-512.png" "$PLAY_DIR/feature-graphic-1024x500.png"
