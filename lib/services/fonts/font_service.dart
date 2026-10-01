import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class FontOption {
  const FontOption({
    required this.id,
    required this.displayName,
    required this.family,
    /// Family name used by libass / FFmpeg (may differ from Flutter family).
    this.assFontName,
    this.assetRegular,
    this.assetBold,
    this.isSystemFallback = false,
  });

  final String id;
  final String displayName;
  final String family;
  final String? assFontName;
  final String? assetRegular;
  final String? assetBold;
  final bool isSystemFallback;

  String get exportFontName => assFontName ?? family;
}

/// Font manager — extracts bundled TTFs so FFmpeg can burn-in captions.
class FontService {
  FontService();

  static const defaultFontId = 'noto_sans_arabic';

  final List<FontOption> _fonts = [
    const FontOption(
      id: defaultFontId,
      displayName: 'Default Kurdish',
      family: 'NotoSansArabic',
      // Actual TTF family name read by libass:
      assFontName: 'Noto Sans Arabic',
      assetRegular: 'assets/fonts/NotoSansArabic-Regular.ttf',
      assetBold: 'assets/fonts/NotoSansArabic-Bold.ttf',
    ),
    const FontOption(
      id: 'system_arabic',
      displayName: 'System Arabic',
      family: 'sans-serif',
      assFontName: 'sans-serif',
      isSystemFallback: true,
    ),
  ];

  List<FontOption> get availableFonts => List.unmodifiable(_fonts);

  FontOption get defaultFont =>
      _fonts.firstWhere((f) => f.id == defaultFontId, orElse: () => _fonts.first);

  FontOption? findById(String id) {
    for (final f in _fonts) {
      if (f.id == id) return f;
    }
    return null;
  }

  FontOption? findByFamily(String family) {
    for (final f in _fonts) {
      if (f.family == family || f.assFontName == family) return f;
    }
    return null;
  }

  void register(FontOption option) {
    _fonts.removeWhere((f) => f.id == option.id);
    _fonts.add(option);
  }

  /// Copy bundled fonts into a writable directory for FFmpeg `fontsdir=`.
  Future<String?> ensureExportFontsDir() async {
    try {
      final root = await getTemporaryDirectory();
      final dir = Directory(p.join(root.path, 'montage_fonts'));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      var wrote = false;
      for (final font in _fonts) {
        for (final asset in [font.assetRegular, font.assetBold]) {
          if (asset == null) continue;
          final name = p.basename(asset);
          final out = File(p.join(dir.path, name));
          if (!await out.exists() || await out.length() < 1000) {
            final data = await rootBundle.load(asset);
            await out.writeAsBytes(
              data.buffer.asUint8List(
                data.offsetInBytes,
                data.lengthInBytes,
              ),
              flush: true,
            );
          }
          wrote = true;
        }
      }
      return wrote ? dir.path : null;
    } catch (_) {
      return null;
    }
  }

  /// ASS Fontname for a Flutter family id.
  String assFontNameFor(String flutterFamily) {
    return findByFamily(flutterFamily)?.exportFontName ?? 'Noto Sans Arabic';
  }
}
