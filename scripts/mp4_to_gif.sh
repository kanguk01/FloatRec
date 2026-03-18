#!/bin/bash
# MP4 → README용 최적화 GIF 변환
# Usage: ./scripts/mp4_to_gif.sh input.mp4 [output.gif] [width]
#
# Examples:
#   ./scripts/mp4_to_gif.sh demo.mp4                    # → demo.gif (640px)
#   ./scripts/mp4_to_gif.sh demo.mp4 assets/demo.gif    # 경로 지정
#   ./scripts/mp4_to_gif.sh demo.mp4 demo.gif 800       # 800px 너비

set -euo pipefail

INPUT="${1:?Usage: $0 input.mp4 [output.gif] [width]}"
OUTPUT="${2:-${INPUT%.mp4}.gif}"
WIDTH="${3:-640}"
FPS=15

if [ ! -f "$INPUT" ]; then
    echo "Error: $INPUT not found"
    exit 1
fi

OUTPUT_DIR=$(dirname "$OUTPUT")
[ -d "$OUTPUT_DIR" ] || mkdir -p "$OUTPUT_DIR"

echo "Converting: $INPUT → $OUTPUT (${WIDTH}px, ${FPS}fps)"

# 2-pass 팔레트 방식으로 고품질 GIF 생성
PALETTE=$(mktemp /tmp/palette-XXXXXX.png)
trap 'rm -f "$PALETTE"' EXIT

ffmpeg -y -i "$INPUT" \
    -vf "fps=${FPS},scale=${WIDTH}:-1:flags=lanczos,palettegen=stats_mode=diff" \
    "$PALETTE" 2>/dev/null

ffmpeg -y -i "$INPUT" -i "$PALETTE" \
    -lavfi "fps=${FPS},scale=${WIDTH}:-1:flags=lanczos[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle" \
    "$OUTPUT" 2>/dev/null

SIZE=$(du -h "$OUTPUT" | cut -f1 | xargs)
echo "Done: $OUTPUT ($SIZE)"
