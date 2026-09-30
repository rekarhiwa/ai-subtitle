# Bundled Windows FFmpeg

Place `ffmpeg.exe` and `ffprobe.exe` in this folder.

The app resolves binaries in this order:

1. Explicit override
2. `third_party/ffmpeg/windows/ffmpeg.exe` (from project root when running in debug)
3. Next to the built executable
4. System PATH

Prefer a build that includes **libass** (subtitle/ass filters) for burn-in export.
