# compyssor-ffmpeg

Builds do FFmpeg (LGPL 2.1) baixadas automaticamente pelo Compyssor.

| Plataforma | Origem |
|---|---|
| macOS arm64 / x86_64 | Compilado aqui por [`scripts/build-macos.sh`](scripts/build-macos.sh) |
| Windows x86_64 / arm64 | Cópia da [BtbN/FFmpeg-Builds](https://github.com/BtbN/FFmpeg-Builds) (LGPL) |
| Linux x86_64 / arm64 | Cópia da [BtbN/FFmpeg-Builds](https://github.com/BtbN/FFmpeg-Builds) (LGPL) |

Os arquivos ficam nos [Releases](../../releases), com os hashes em `SHA256SUMS`.

## Conteúdo da build de macOS

FFmpeg 8.1.3 estático, sem componentes GPL ou não livres:

- VideoToolbox / AudioToolbox (Apple)
- libvpx (VP9), libopus, libmp3lame, libvorbis
- zimg (conversão de HDR)
- OpenH264 (H.264 por CPU)

Cada código-fonte tem versão e SHA-256 fixos no script. O arquivo
`SOURCE.txt` dentro de cada pacote lista as fontes e a configuração
usada, como pede a LGPL.

## Gerar um novo release

Actions → **Build FFmpeg** → *Run workflow*, informando a tag
(ex.: `ffmpeg-8.1.3-2`). Depois, atualize as URLs e hashes em
`ffmpeg_manager.py` no Compyssor.
