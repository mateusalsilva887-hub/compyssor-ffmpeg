#!/usr/bin/env bash
#
# Testa um pacote do FFmpeg já montado: componentes obrigatórios e
# codificação de verdade com fontes sintéticas.
#
# Uso: scripts/test-ffmpeg.sh <pasta do pacote> <encoders H.264 de GPU...>
#   ex.: scripts/test-ffmpeg.sh build/ffmpeg-8.1.3-macos-arm64 h264_videotoolbox

set -euo pipefail

PACKAGE="$1"
shift
GPU_ENCODERS=("$@")

FFMPEG="$PACKAGE/bin/ffmpeg"
FFPROBE="$PACKAGE/bin/ffprobe"

if [ -f "$FFMPEG.exe" ]; then
  FFMPEG="$FFMPEG.exe"
  FFPROBE="$FFPROBE.exe"
fi

TEST="$(mktemp -d)"

echo "=== versão ==="
"$FFMPEG" -hide_banner -version | head -3
"$FFPROBE" -hide_banner -version | head -1

echo
echo "=== componentes obrigatórios ==="
missing=0

check() {
  local kind="$1" name="$2"

  if ! "$FFMPEG" -hide_banner "-$kind" 2>/dev/null | grep -q " $name "; then
    echo "FALTANDO ($kind): $name"
    missing=1
  fi
}

for encoder in libvpx-vp9 libopenh264 aac flac libmp3lame libopus libvorbis pcm_s16le wmav2 "${GPU_ENCODERS[@]}"; do
  check encoders "$encoder"
done

for muxer in adts asf avi flac ipod matroska mov mp3 mp4 ogg opus wav webm; do
  check muxers "$muxer"
done

for filter in setparams zscale tonemap scale aresample; do
  check filters "$filter"
done

# Decodificadores comuns em arquivos de câmera e de edição
for decoder in h264 hevc prores dnxhd av1 vp9 mpeg2video mjpeg pcm_s24le aac mp3; do
  check decoders "$decoder"
done

for protocol in http https tcp; do
  if "$FFMPEG" -hide_banner -protocols 2>/dev/null | grep -qx "  $protocol"; then
    echo "NÃO DEVERIA EXISTIR (protocolo de rede): $protocol"
    missing=1
  fi
done

[ "$missing" = 0 ] || exit 1
echo "ok"

echo
echo "=== codificação ==="

run_test() {
  local output="$1"
  shift

  "$FFMPEG" -hide_banner -loglevel error -y \
    -f lavfi -i testsrc2=s=320x240:d=2 \
    -f lavfi -i sine=d=2 \
    -shortest "$@" "$TEST/$output"

  local size
  size="$(wc -c < "$TEST/$output" | tr -d ' ')"

  if [ "$size" -eq 0 ]; then
    echo "falhou: $output (arquivo vazio)"
    return 1
  fi

  echo "ok: $output ($size bytes)"
}

run_test vp9.webm -c:v libvpx-vp9 -crf 30 -b:v 0 -c:a libopus
run_test openh264.mp4 -c:v libopenh264 -pix_fmt yuv420p -c:a aac
run_test mp3.mp3 -vn -c:a libmp3lame
run_test vorbis.ogg -vn -c:a libvorbis
run_test wma.wma -vn -c:a wmav2
run_test flac.flac -vn -c:a flac
run_test 10bit.mkv -vf format=yuv420p10le,format=yuv420p -c:v libopenh264 -c:a aac
# O testsrc2 não tem metadados de cor; setparams simula um HDR10
run_test tonemap.mkv -vf "setparams=color_primaries=bt2020:color_trc=smpte2084:colorspace=bt2020nc,zscale=t=linear:npl=100,format=gbrpf32le,zscale=p=bt709,tonemap=tonemap=hable,zscale=t=bt709:m=bt709:r=tv,format=yuv420p" -c:v libopenh264 -c:a aac

# O ffprobe precisa conseguir ler o que o ffmpeg gravou
"$FFPROBE" -v error -show_entries stream=codec_name -of csv=p=0 "$TEST/vp9.webm" | tr '\n' ' '
echo "(ffprobe ok)"

# As máquinas de CI não têm GPU: só informa
for encoder in "${GPU_ENCODERS[@]}"; do
  run_test "$encoder.mp4" -c:v "$encoder" -c:a aac \
    || echo "aviso: $encoder indisponível nesta máquina de CI"
done

rm -rf "$TEST"
