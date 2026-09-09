#!/bin/bash
# shellcheck disable=SC2034
# FFmpeg — Homebrew formula. Command-line audio/video converter; also what
# yt-dlp calls to merge separate video and audio streams.
APP_NAME="FFmpeg"
APP_CATEGORY="Media"

ffmpeg_install()   { formula_install ffmpeg; }
ffmpeg_update()    { formula_update ffmpeg; }
ffmpeg_uninstall() { formula_uninstall ffmpeg "$1"; }
ffmpeg_installed() { formula_installed ffmpeg; }
