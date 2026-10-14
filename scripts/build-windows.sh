#!/usr/bin/env bash
#
# Compila um FFmpeg LGPL para Windows x86_64 a partir do Linux
# (MinGW-w64), com os codecs usados pelo Compyssor e os encoders de
# GPU (NVIDIA NVENC, AMD AMF, Intel Quick Sync, Media Foundation).
#
# As dependências são compiladas do código-fonte com versão e
# SHA-256 fixos e entram estáticas nas DLLs do FFmpeg.
#
# Saída: dist/ffmpeg-<versão>-windows-x86_64.zip

set -euo pipefail

FFMPEG_VERSION="8.1.3"

HOST="x86_64-w64-mingw32"
ROOT="$(pwd)"
SRC="$ROOT/build/src"
PREFIX="$ROOT/build/prefix"
DIST="$ROOT/dist"
JOBS="$(nproc)"

# Variante "posix" do MinGW: suporte a std::thread nas bibliotecas C++
export CC="$HOST-gcc-posix"
export CXX="$HOST-g++-posix"
export AR="$HOST-ar"
export RANLIB="$HOST-ranlib"
export STRIP="$HOST-strip"
export CFLAGS="-O2"
export CXXFLAGS="-O2"
export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"

mkdir -p "$SRC" "$PREFIX/include" "$PREFIX/lib/pkgconfig" "$DIST"

# nome|url|sha256
SOURCES=(
  "ffmpeg|https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz|7138d28c96d9d3e3af4ee3d8cad72741f8ffb40da90c1112235dea3ecd3178a3"
  "zlib|https://github.com/madler/zlib/releases/download/v1.3.1/zlib-1.3.1.tar.gz|9a93b2b7dfdac77ceba5a558a580e74667dd6fede4585b91eefb60f03b72df23"
  "lame|https://downloads.sourceforge.net/project/lame/lame/3.100/lame-3.100.tar.gz|ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e"
  "libogg|https://downloads.xiph.org/releases/ogg/libogg-1.3.6.tar.xz|5c8253428e181840cd20d41f3ca16557a9cc04bad4a3d04cce84808677fa1061"
  "libvorbis|https://downloads.xiph.org/releases/vorbis/libvorbis-1.3.7.tar.xz|b33cc4934322bcbf6efcbacf49e3ca01aadbea4114ec9589d1b1e9d20f72954b"
  "opus|https://downloads.xiph.org/releases/opus/opus-1.5.2.tar.gz|65c1d2f78b9f2fb20082c38cbe47c951ad5839345876e46941612ee87f9a7ce1"
  "libvpx|https://github.com/webmproject/libvpx/archive/refs/tags/v1.15.2.tar.gz|26fcd3db88045dee380e581862a6ef106f49b74b6396ee95c2993a260b4636aa"
  "zimg|https://github.com/sekrit-twc/zimg/archive/refs/tags/release-3.0.6.tar.gz|be89390f13a5c9b2388ce0f44a5e89364a20c1c57ce46d382b1fcc3967057577"
  "openh264|https://github.com/cisco/openh264/archive/refs/tags/v2.6.0.tar.gz|558544ad358283a7ab2930d69a9ceddf913f4a51ee9bf1bfb9e377322af81a69"
  "nv-codec-headers|https://github.com/FFmpeg/nv-codec-headers/releases/download/n11.1.5.3/nv-codec-headers-11.1.5.3.tar.gz|2974b91062197e0527dffa3aadd8fe3bfa6681ae45f5ff9181bc0ca6479abd59"
  "amf-headers|https://github.com/GPUOpen-LibrariesAndSDKs/AMF/releases/download/v1.5.3/AMF-headers-v1.5.3.tar.gz|570c8f6593b8c24a6e47a0a9c59b216a7198138e660ba4011590ae913343d5c3"
  "libvpl|https://github.com/intel/libvpl/archive/refs/tags/v2.17.0.tar.gz|4de3e2faf1e8307fb282e4a43f443191810f6a6b0a484fffa7995ba1c814c6ec"
)

log() {
  echo
  echo "=== $* ==="
}

fetch() {
  local name="$1" url="$2" sha="$3"
  local archive="$SRC/$name.archive"

  log "download $name"
  curl -fsSL --retry 5 --retry-delay 5 -o "$archive" "$url"
  echo "$sha  $archive" | sha256sum -c -

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
    --host="$HOST" \
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

log "build zlib"
cd "$SRC/zlib"
make -f win32/Makefile.gcc -j"$JOBS" PREFIX="$HOST-" libz.a
install -m 644 zlib.h zconf.h "$PREFIX/include/"
install -m 644 libz.a "$PREFIX/lib/"
cd "$ROOT"

autotools_build libogg

autotools_build libvorbis --disable-docs --disable-examples

autotools_build opus --disable-doc --disable-extra-programs

# lame 3.100 exporta um símbolo que não existe (mesma correção do
# Homebrew e da BtbN)
sed -i '/lame_init_old/d' "$SRC/lame/include/libmp3lame.sym"
autotools_build lame --disable-frontend --disable-decoder

log "build zimg"
cd "$SRC/zimg"
./autogen.sh
./configure --host="$HOST" --prefix="$PREFIX" --disable-shared --enable-static
make -j"$JOBS"
make install
cd "$ROOT"

log "build libvpx"
cd "$SRC/libvpx"
CROSS="$HOST-" ./configure \
  --prefix="$PREFIX" \
  --target=x86_64-win64-gcc \
  --disable-shared \
  --enable-static \
  --disable-examples \
  --disable-tools \
  --disable-docs \
  --disable-unit-tests
CROSS="$HOST-" make -j"$JOBS"
make install
cd "$ROOT"

log "build openh264"
cd "$SRC/openh264"
make -j"$JOBS" OS=mingw_nt ARCH=x86_64 \
  CC="$CC" CXX="$CXX" AR="$AR" \
  PREFIX="$PREFIX" install-static
cd "$ROOT"

log "nv-codec-headers"
make -C "$SRC/nv-codec-headers" PREFIX="$PREFIX" install

log "amf-headers"
cp -r "$SRC/amf-headers/AMF" "$PREFIX/include/"

log "build libvpl"
cmake -S "$SRC/libvpl" -B "$SRC/libvpl/build" \
  -DCMAKE_SYSTEM_NAME=Windows \
  -DCMAKE_C_COMPILER="$CC" \
  -DCMAKE_CXX_COMPILER="$CXX" \
  -DCMAKE_RC_COMPILER="$HOST-windres" \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=OFF \
  -DBUILD_TOOLS=OFF \
  -DBUILD_EXAMPLES=OFF \
  -DBUILD_TESTS=OFF \
  -DINSTALL_EXAMPLES=OFF
cmake --build "$SRC/libvpl/build" -j"$JOBS"
cmake --install "$SRC/libvpl/build"

# zimg, OpenH264 e libvpl são C++ e precisam da libstdc++, que nem
# todos os .pc declaram. "-l:libstdc++.a" força a versão estática:
# com "-lstdc++" o linker misturava a estática e a DLL.
for pc in zimg openh264 vpl; do
  file="$PREFIX/lib/pkgconfig/$pc.pc"
  sed -i "s/-lstdc++/-l:libstdc++.a/g" "$file"

  if ! grep -q "^Libs.private:" "$file"; then
    echo "Libs.private:" >> "$file"
  fi

  if ! grep -q "^Libs.private:.*-l:libstdc++.a" "$file"; then
    sed -i "s/^Libs.private:.*/& -l:libstdc++.a/" "$file"
  fi

  grep "^Libs" "$file"
done

# ------------------------------------------------------------
# FFmpeg
# ------------------------------------------------------------

source "$ROOT/scripts/ffmpeg-components.sh"

# As DLLs do FFmpeg ficam ao lado de ffmpeg.exe e ffprobe.exe.
# libgcc, libstdc++ e winpthread entram estáticos: o pacote só
# depende de DLLs do próprio Windows.
FFMPEG_CONFIGURE=(
  --prefix="$PREFIX"
  "${FFMPEG_COMMON_CONFIGURE[@]}"
  --target-os=mingw32
  --arch=x86_64
  --cross-prefix="$HOST-"
  --cc="$CC"
  --cxx="$CXX"
  --pkg-config=pkg-config
  --enable-w32threads
  --enable-d3d11va
  --enable-dxva2
  --enable-ffnvcodec
  --enable-nvenc
  --enable-amf
  --enable-libvpl
  --enable-mediafoundation
  --enable-encoder=h264_nvenc,h264_amf,h264_qsv,h264_mf
  --extra-cflags="-I$PREFIX/include"
  # -static: o linker usa sempre a versão estática das bibliotecas
  # (libgcc, libstdc++, winpthread); as do Windows continuam DLLs
  --extra-ldflags="-L$PREFIX/lib -static -static-libgcc -static-libstdc++"
  --extra-libs="-l:libstdc++.a"
)

log "build ffmpeg"
cd "$SRC/ffmpeg"
if ! ./configure "${FFMPEG_CONFIGURE[@]}"; then
  tail -n 60 ffbuild/config.log
  exit 1
fi
make -j"$JOBS"
make install
cd "$ROOT"

# ------------------------------------------------------------
# Pacote
# ------------------------------------------------------------

log "pacote"
NAME="ffmpeg-${FFMPEG_VERSION}-windows-x86_64"
PACKAGE="$ROOT/build/$NAME"
rm -rf "$PACKAGE"
mkdir -p "$PACKAGE/bin"

cp "$PREFIX/bin/ffmpeg.exe" "$PREFIX/bin/ffprobe.exe" "$PREFIX"/bin/*.dll "$PACKAGE/bin/"
"$STRIP" "$PACKAGE"/bin/*

log "dependências das DLLs"
package_dlls="$(cd "$PACKAGE/bin" && ls *.dll | tr '[:upper:]' '[:lower:]')"
problem=0

for binary in "$PACKAGE"/bin/*; do
  for dll in $("$HOST-objdump" -p "$binary" | awk '/DLL Name:/ {print tolower($3)}'); do
    if echo "$package_dlls" | grep -qx "$dll"; then
      continue
    fi

    # Runtimes do MinGW não podem aparecer: estão estáticos
    if [[ "$dll" =~ ^(libgcc|libstdc|libwinpthread) ]]; then
      echo "ERRO: $(basename "$binary") depende de $dll"
      problem=1
    fi
  done
done

"$HOST-objdump" -p "$PACKAGE/bin/ffmpeg.exe" | awk '/DLL Name:/ {print "  " $3}'
[ "$problem" = 0 ] || exit 1

cp "$SRC/ffmpeg/COPYING.LGPLv2.1" "$PACKAGE/LICENSE.txt"
write_source_txt "$PACKAGE/SOURCE.txt" "build LGPL para Windows x86_64" "${FFMPEG_CONFIGURE[@]}"
collect_licenses "$PACKAGE"

du -sh "$PACKAGE"
ls -la "$PACKAGE/bin"

cd "$ROOT/build"
rm -f "$DIST/$NAME.zip"
zip -r -9 "$DIST/$NAME.zip" "$NAME"
sha256sum "$DIST/$NAME.zip"
