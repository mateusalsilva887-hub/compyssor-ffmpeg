#!/usr/bin/env bash
#
# Compila um FFmpeg LGPL estático para macOS (arquitetura da máquina
# atual: arm64 ou x86_64) com os codecs usados pelo Compyssor.
#
# Todas as dependências são compiladas a partir do código-fonte, com
# versão e SHA-256 fixos. O pkg-config é restrito ao prefixo local
# para que nada do Homebrew seja vinculado por acidente.
#
# Saída: dist/ffmpeg-<versão>-macos-<arch>.tar.xz

set -euo pipefail

FFMPEG_VERSION="8.1.3"

ARCH="$(uname -m)"
ROOT="$(pwd)"
SRC="$ROOT/build/src"
PREFIX="$ROOT/build/prefix"
DIST="$ROOT/dist"
JOBS="$(sysctl -n hw.ncpu)"

export MACOSX_DEPLOYMENT_TARGET="11.0"
export CFLAGS="-O2 -mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET"
export CXXFLAGS="$CFLAGS"
export LDFLAGS="-mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET"
export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"

mkdir -p "$SRC" "$PREFIX" "$DIST"

# nome|url|sha256
SOURCES=(
  "ffmpeg|https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz|7138d28c96d9d3e3af4ee3d8cad72741f8ffb40da90c1112235dea3ecd3178a3"
  "lame|https://downloads.sourceforge.net/project/lame/lame/3.100/lame-3.100.tar.gz|ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e"
  "libogg|https://downloads.xiph.org/releases/ogg/libogg-1.3.6.tar.xz|5c8253428e181840cd20d41f3ca16557a9cc04bad4a3d04cce84808677fa1061"
  "libvorbis|https://downloads.xiph.org/releases/vorbis/libvorbis-1.3.7.tar.xz|b33cc4934322bcbf6efcbacf49e3ca01aadbea4114ec9589d1b1e9d20f72954b"
  "opus|https://downloads.xiph.org/releases/opus/opus-1.5.2.tar.gz|65c1d2f78b9f2fb20082c38cbe47c951ad5839345876e46941612ee87f9a7ce1"
  "libvpx|https://github.com/webmproject/libvpx/archive/refs/tags/v1.15.2.tar.gz|26fcd3db88045dee380e581862a6ef106f49b74b6396ee95c2993a260b4636aa"
  "zimg|https://github.com/sekrit-twc/zimg/archive/refs/tags/release-3.0.6.tar.gz|be89390f13a5c9b2388ce0f44a5e89364a20c1c57ce46d382b1fcc3967057577"
  "openh264|https://github.com/cisco/openh264/archive/refs/tags/v2.6.0.tar.gz|558544ad358283a7ab2930d69a9ceddf913f4a51ee9bf1bfb9e377322af81a69"
)

log() {
  echo
  echo "=== $* ==="
}

# Baixa, confere o SHA-256 e extrai em $SRC/<nome>
fetch() {
  local name="$1" url="$2" sha="$3"
  local archive="$SRC/$name.archive"

  log "download $name"
  curl -fsSL --retry 5 --retry-delay 5 -o "$archive" "$url"
  echo "$sha  $archive" | shasum -a 256 -c -

  rm -rf "${SRC:?}/$name"
  mkdir -p "$SRC/$name"
  tar -xf "$archive" -C "$SRC/$name" --strip-components 1
}

for entry in "${SOURCES[@]}"; do
  IFS="|" read -r name url sha <<< "$entry"
  fetch "$name" "$url" "$sha"
done

autotools_build() {
  local name="$1"
  shift

  log "build $name"
  cd "$SRC/$name"
  ./configure \
    --prefix="$PREFIX" \
    --disable-shared \
    --enable-static \
    "$@"
  make -j"$JOBS"
  make install
  cd "$ROOT"
}

# ------------------------------------------------------------
# Dependências
# ------------------------------------------------------------

autotools_build libogg

# O configure do libvorbis 1.3.7 passa -force_cpusubtype_ALL, que o
# linker atual da Apple recusa (mesma correção usada pelo Homebrew).
sed -i '' 's/ -force_cpusubtype_ALL//g' "$SRC/libvorbis/configure"
autotools_build libvorbis \
  --disable-docs \
  --disable-examples

autotools_build opus \
  --disable-doc \
  --disable-extra-programs

# lame 3.100 exporta um símbolo que não existe; o linker do macOS
# recusa (mesma correção usada pelo Homebrew).
sed -i '' '/lame_init_old/d' "$SRC/lame/include/libmp3lame.sym"
autotools_build lame \
  --disable-frontend \
  --disable-debug

log "build zimg"
cd "$SRC/zimg"
./autogen.sh
./configure --prefix="$PREFIX" --disable-shared --enable-static
make -j"$JOBS"
make install
cd "$ROOT"

log "build libvpx"
if [ "$ARCH" = "arm64" ]; then
  VPX_TARGET="arm64-darwin20-gcc"
else
  VPX_TARGET="x86_64-darwin20-gcc"
fi
cd "$SRC/libvpx"
./configure \
  --prefix="$PREFIX" \
  --target="$VPX_TARGET" \
  --disable-shared \
  --enable-static \
  --enable-pic \
  --disable-examples \
  --disable-tools \
  --disable-docs \
  --disable-unit-tests
make -j"$JOBS"
make install
cd "$ROOT"

log "build openh264"
cd "$SRC/openh264"
make -j"$JOBS" OS=darwin ARCH="$ARCH" PREFIX="$PREFIX" install-static
cd "$ROOT"

# ------------------------------------------------------------
# FFmpeg
# ------------------------------------------------------------

source "$ROOT/scripts/ffmpeg-components.sh"

# Bibliotecas compartilhadas em lib/, encontradas pelo ffmpeg e pelo
# ffprobe (em bin/) através de @executable_path.
FFMPEG_CONFIGURE=(
  --prefix="$PREFIX"
  "${FFMPEG_COMMON_CONFIGURE[@]}"
  --install-name-dir="@executable_path/../lib"
  --enable-videotoolbox
  --enable-audiotoolbox
  --enable-encoder=h264_videotoolbox
  --extra-cflags="$CFLAGS -I$PREFIX/include"
  --extra-ldflags="$LDFLAGS -L$PREFIX/lib"
  --extra-libs="-lc++"
)

log "build ffmpeg"
cd "$SRC/ffmpeg"
./configure "${FFMPEG_CONFIGURE[@]}"
make -j"$JOBS"
make install
cd "$ROOT"

# ------------------------------------------------------------
# Pacote
# ------------------------------------------------------------

log "pacote"
NAME="ffmpeg-${FFMPEG_VERSION}-macos-${ARCH}"
PACKAGE="$ROOT/build/$NAME"
rm -rf "$PACKAGE"
mkdir -p "$PACKAGE/bin" "$PACKAGE/lib"

cp "$PREFIX/bin/ffmpeg" "$PREFIX/bin/ffprobe" "$PACKAGE/bin/"

# Só as bibliotecas do FFmpeg, pelo nome que os binários procuram
# (ex.: libavcodec.62.dylib); as dependências são estáticas.
for library in $(otool -L "$PACKAGE/bin/ffmpeg" "$PACKAGE/bin/ffprobe" | grep -o '@executable_path/../lib/[^ ]*' | sort -u); do
  cp -L "$PREFIX/lib/$(basename "$library")" "$PACKAGE/lib/"
done

strip -x "$PACKAGE"/bin/* "$PACKAGE"/lib/*
# strip invalida a assinatura ad-hoc; Apple Silicon exige uma
codesign --force --sign - "$PACKAGE"/lib/* "$PACKAGE"/bin/*

log "bibliotecas dinâmicas"
for binary in "$PACKAGE"/bin/* "$PACKAGE"/lib/*; do
  otool -L "$binary"

  # Só bibliotecas do macOS ou do próprio pacote
  if otool -L "$binary" | tail -n +2 | grep -v -E "^\s+(/usr/lib/|/System/Library/|@executable_path/../lib/)"; then
    echo "ERRO: $binary depende de bibliotecas de fora do pacote"
    exit 1
  fi
done

cp "$SRC/ffmpeg/COPYING.LGPLv2.1" "$PACKAGE/LICENSE.txt"
write_source_txt "$PACKAGE/SOURCE.txt" "build LGPL para macOS ${ARCH}" "${FFMPEG_CONFIGURE[@]}"
collect_licenses "$PACKAGE"

du -sh "$PACKAGE"

# ------------------------------------------------------------
# Testes
# ------------------------------------------------------------

log "testes"
bash "$ROOT/scripts/test-ffmpeg.sh" "$PACKAGE" h264_videotoolbox

mkdir -p "$DIST"
tar -C "$ROOT/build" -cJf "$DIST/$NAME.tar.xz" "$NAME"
shasum -a 256 "$DIST/$NAME.tar.xz"
