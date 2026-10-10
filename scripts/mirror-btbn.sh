#!/usr/bin/env bash
#
# Copia as builds LGPL de Windows e Linux da BtbN para este
# repositório, conferindo o SHA-256 publicado pela BtbN. Assim o
# Compyssor não depende da BtbN manter os arquivos para sempre.
#
# Saída: dist/

set -euo pipefail

BTBN="https://github.com/BtbN/FFmpeg-Builds/releases/download/autobuild-2026-09-30-13-08"
BUILD="ffmpeg-n8.1.3-9-g29e619e767"

# arquivo de origem|nome no release|sha256
FILES=(
  "$BUILD-win64-lgpl-8.1.zip|ffmpeg-8.1.3-windows-x86_64.zip|4a7642b2264c03e8a0ce8a3825b933ee5580656f45695a086fe7e294045ffc0a"
  "$BUILD-winarm64-lgpl-8.1.zip|ffmpeg-8.1.3-windows-arm64.zip|9e49da7acb363b60bf60f9efad2ac0281cf68d43930ec4b1b8dd6a4f20dd7e5f"
  "$BUILD-linux64-lgpl-8.1.tar.xz|ffmpeg-8.1.3-linux-x86_64.tar.xz|dfa863a00ca81f1bdf58a372b18cff4820f0017e55de32778de8ecd8ed92a02e"
  "$BUILD-linuxarm64-lgpl-8.1.tar.xz|ffmpeg-8.1.3-linux-arm64.tar.xz|8463881ca7a25015ca6e00f5c91dd2f1637eb73d33c8230413cb74db760a86b3"
)

mkdir -p dist

for entry in "${FILES[@]}"; do
  IFS="|" read -r source target sha <<< "$entry"

  echo "=== $target ==="
  curl -fsSL --retry 5 --retry-delay 5 -o "dist/$target" "$BTBN/$source"
  echo "$sha  dist/$target" | sha256sum -c -
done
