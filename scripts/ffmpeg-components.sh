# Componentes do FFmpeg usados pelo Compyssor (incluído pelos
# scripts de build de cada sistema).
#
# Entrada: todos os decodificadores e formatos, para abrir qualquer
# arquivo que o usuário tenha.
# Saída: só os encoders, formatos e filtros que o Compyssor usa.
# Rede: desligada; o FFmpeg só lê e grava arquivos locais.

FFMPEG_ENCODERS=(
  # vídeo
  libvpx_vp9
  libopenh264
  # áudio
  aac
  flac
  libmp3lame
  libopus
  libvorbis
  pcm_s16le
  wmav2
)

FFMPEG_MUXERS=(
  adts      # .aac
  asf       # .wma
  avi
  flac
  ipod      # .m4a
  matroska  # .mkv
  mov
  mp3
  mp4
  null      # teste de encoder (-f null)
  ogg
  opus
  wav
  webm
)

FFMPEG_FILTERS=(
  # usados pelo FFmpeg internamente (conversões, -t, rotação); os de
  # entrada e saída do grafo (buffer, buffersink...) são sempre incluídos
  format aformat scale aresample null anull copy
  trim atrim setpts asetpts fps
  transpose hflip vflip
  # conversão de HDR
  setparams zscale tonemap
  # fontes sintéticas (teste de encoder e testes do build)
  color testsrc2 sine anullsrc
)

# Escreve o SOURCE.txt do pacote (exigido pela LGPL): de onde vem o
# código-fonte de cada componente e como o FFmpeg foi configurado.
# Uso: write_source_txt <arquivo> <descrição> <configure...>
write_source_txt() {
  local file="$1" description="$2"
  shift 2

  {
    echo "FFmpeg ${FFMPEG_VERSION} — ${description}"
    echo "Compilado por https://github.com/${GITHUB_REPOSITORY:-local}"
    echo
    echo "Licença: LGPL 2.1 (ver LICENSE.txt)."
    echo "Pela LGPL, o código-fonte correspondente está disponível em:"
    echo

    local entry name url sha
    for entry in "${SOURCES[@]}"; do
      IFS="|" read -r name url sha <<< "$entry"
      echo "  $name"
      echo "    $url"
      echo "    sha256: $sha"
    done

    echo
    echo "Configuração do FFmpeg:"
    echo "  $*"
  } > "$file"
}

join_by_comma() {
  local IFS=","
  echo "$*"
}

FFMPEG_COMMON_CONFIGURE=(
  --disable-gpl
  --disable-nonfree
  --disable-version3
  --disable-autodetect
  --disable-debug
  --disable-doc
  --disable-ffplay
  --enable-shared
  --disable-static
  --pkg-config-flags=--static
  --disable-network
  --disable-protocols
  --enable-protocol=file,pipe
  --disable-devices
  --enable-indev=lavfi
  --disable-encoders
  --enable-encoder="$(join_by_comma "${FFMPEG_ENCODERS[@]}")"
  --disable-muxers
  --enable-muxer="$(join_by_comma "${FFMPEG_MUXERS[@]}")"
  --disable-filters
  --enable-filter="$(join_by_comma "${FFMPEG_FILTERS[@]}")"
  --enable-zlib
  --enable-libvpx
  --enable-libopus
  --enable-libmp3lame
  --enable-libvorbis
  --enable-libzimg
  --enable-libopenh264
)
