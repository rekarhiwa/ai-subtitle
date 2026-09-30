# AI Subtitle

Production-oriented Flutter app for **automatic Kurdish Sorani (Central Kurdish) video subtitles**.

Pipeline (fully local processing except Gemini transcription):

```
Video → Local FFmpeg (extract audio) → Gemini API → Subtitle editor
  → Local FFmpeg (ASS burn-in) → Final MP4
```

No login, no backend, no VPS. The user supplies their own Gemini API key.

## Features (MVP)

- Select video (Windows / Android)
- Extract mono 16 kHz AAC audio locally
- Transcribe with Gemini (`gemini-3.8-flash`, configurable in one place)
- Edit text / timing, split, merge, add, delete segments
- Live Flutter overlay preview (style + animations)
- Presets: Clean / Bold / Minimal
- Animations: None / Fade / Pop / Slide Up
- Export SRT, ASS, and burned-in MP4
- Secure API key storage (`flutter_secure_storage`)

## Install

### Prerequisites

- Flutter 3.24+ (tested with Flutter 3.44 / Dart 3.12)
- Windows 10/11 **or** Android SDK for mobile builds
- A Gemini API key from [Google AI Studio](https://aistudio.google.com/apikey)

```bash
git clone <this-repo>
cd subtitle
flutter pub get
# Windows only — download bundled FFmpeg if missing:
powershell -ExecutionPolicy Bypass -File tool/download_ffmpeg_windows.ps1
```

## Gemini API key

1. Run the app
2. Open **Settings**
3. Paste your Gemini API key
4. Tap **Test API Key** → should show **API connected**
5. Tap **Save Key**

The key is stored with `flutter_secure_storage`. **Never commit API keys.**

Change the model in one place:

`lib/core/config/gemini_config.dart` → `GeminiConfig.model`

The transcription prompt lives in:

`assets/prompts/transcription_prompt.txt`

## FFmpeg configuration

### Windows (Process + bundled binary)

This project expects FFmpeg binaries at:

```
third_party/ffmpeg/windows/ffmpeg.exe
third_party/ffmpeg/windows/ffprobe.exe
```

A Gyan.dev essentials build is already downloaded into that folder for development.

Resolution order:

1. Explicit override path
2. `third_party/ffmpeg/windows/ffmpeg.exe` (project root)
3. Next to the built executable
4. System `PATH`

For release builds, copy `ffmpeg.exe` / `ffprobe.exe` next to `ai_subtitle.exe`, or keep them under the project path when running from source.

Architecture:

- `VideoProcessingService` — shared interface
- `WindowsVideoProcessingService` — Dart `Process`
- `AndroidVideoProcessingService` — maintained `ffmpeg_kit_flutter_new`
- `FFmpegService` — facade chosen at runtime

### Android

Uses **`ffmpeg_kit_flutter_new`** (actively maintained FFmpeg Kit fork, FFmpeg 8.x). No separate binary install is required for Android.

## Run on Windows

```bash
flutter pub get
flutter run -d windows
```

Or release:

```bash
flutter build windows
```

Then copy FFmpeg binaries next to the generated `.exe` if needed:

```
build/windows/x64/runner/Release/
```

## Build Android

```bash
flutter build apk --release
# or
flutter build appbundle --release
```

Grant storage / media permissions when prompted so the app can read videos.

## Subtitle style architecture

All appearance comes from `SubtitleStyle` (`lib/models/subtitle_style.dart`):

- font, size, weight, colors
- outline + shadow
- normalized `positionX` / `positionY` (0–1) so 9:16, 16:9, 1:1 all work
- max width as a fraction of video width

Preview uses Flutter widgets (`AnimatedSubtitleWidget`).

Export generates an **ASS** file from the same `SubtitleStyle`, then FFmpeg burns it into the MP4.

Presets (`SubtitlePresetCatalog`) only mutate `SubtitleStyle` — they do not duplicate renderers.

## How to add a new font

1. Drop licensed `.ttf` / `.otf` files into `assets/fonts/`
2. Register in `pubspec.yaml` under `flutter/fonts`
3. Register a `FontOption` in `FontService` (`lib/services/fonts/font_service.dart`)
4. Select it in the editor Font dropdown (`SubtitleStyle.fontFamily`)

Kurdish/Arabic text uses `TextDirection.rtl`.

## How to add a new animation

1. Add a value to `SubtitleAnimationType` (or reuse an existing one)
2. Extend `SubtitleAnimationConfig` defaults if needed
3. Implement the visual transform in `AnimatedSubtitleWidget._applyAnimation`
4. Expose it in the editor animation dropdown

Transcription / Gemini code is intentionally **not** coupled to animations.

Phase 2 hooks already reserved:

- `SubtitleAnimationType.wordByWord`
- karaoke / active-word highlighting architecture notes in models

## Project structure

```
lib/
  core/           config, theme, errors, providers, utils
  models/         SubtitleSegment, SubtitleStyle, animations, video metadata
  services/
    gemini/       GeminiService + Files API for large audio
    ffmpeg/       platform video processing
    storage/      secure settings
    fonts/        FontService
    temp/         TempFileService
  features/
    home/
    settings/
    subtitle_editor/
    subtitle_styles/
    subtitle_animations/
    export/
assets/
  fonts/
  prompts/
third_party/ffmpeg/windows/
```

## Tests

```bash
flutter test
flutter analyze
```

Unit coverage includes:

- JSON cleaning / Gemini response parsing
- timestamp conversion
- SRT / ASS generation
- subtitle split / merge

## Privacy

- Original video never uploads to your own server
- Only compressed speech audio is sent to Google Gemini
- Temp files are stored in an app-specific directory and can be cleared from Settings

## License notes

- App code: your project license
- Noto Sans Arabic: SIL Open Font License (Google Fonts)
- FFmpeg: comply with LGPL/GPL of the binaries you distribute
- `ffmpeg_kit_flutter_new`: see package license on pub.dev
