#!/usr/bin/env bash
# Builds the built-in sample stream: Big Buck Bunny as 720p HLS, from the Blender
# Foundation's official file. (c) copyright 2008, Blender Foundation /
# www.bigbuckbunny.org, licensed CC BY 3.0 (https://peach.blender.org/about/).
# The film is kept whole, end credits included, as the licence asks.
# Usage: demo/make_sample.sh <out-dir>   (needs curl, unzip, ffmpeg)
set -euo pipefail

out="${1:?usage: make_sample.sh <out-dir>}"
src_url="https://download.blender.org/peach/bigbuckbunny_movies/big_buck_bunny_720p_h264.mov.zip"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

curl -sSfL -o "$work/bbb.zip" "$src_url"
unzip -q "$work/bbb.zip" -d "$work"
mkdir -p "$out"

# Keyframe every 2s (24 fps) and 4s segments, so playback starts quickly; stereo
# AAC because the source's 5.1 track isn't needed on every TV.
ffmpeg -nostdin -loglevel error -i "$work/big_buck_bunny_720p_h264.mov" \
    -map 0:v:0 -map 0:a:0 \
    -c:v libx264 -preset veryfast -profile:v high -level 4.0 -pix_fmt yuv420p \
    -b:v 2000k -maxrate 2500k -bufsize 4000k -g 48 -keyint_min 48 -sc_threshold 0 \
    -c:a aac -b:a 128k -ac 2 \
    -f hls -hls_time 4 -hls_playlist_type vod \
    -hls_segment_filename "$out/bbb_%03d.ts" "$out/bbb.m3u8"
