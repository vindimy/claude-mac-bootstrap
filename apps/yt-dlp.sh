#!/bin/bash
# shellcheck disable=SC2034
# yt-dlp — Homebrew formula. Video/audio downloader for YouTube and hundreds
# of other sites; the youtube-downloader agent skill drives it. Select ffmpeg
# too: yt-dlp needs it to merge streams and to convert audio.
APP_NAME="yt-dlp"
APP_CATEGORY="Media"

yt_dlp_install()   { formula_install yt-dlp; }
yt_dlp_update()    { formula_update yt-dlp; }
yt_dlp_uninstall() { formula_uninstall yt-dlp "$1"; }
yt_dlp_installed() { formula_installed yt-dlp; }
