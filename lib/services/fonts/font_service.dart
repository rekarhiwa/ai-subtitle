class FontOption {
  const FontOption({
    required this.id,
    required this.displayName,
    required this.family,
    this.assetRegular,
    this.assetBold,
    this.isSystemFallback = false,
  });

  final String id;
  final String displayName;
  final String family;
  final String? assetRegular;
  final String? assetBold;
  final bool isSystemFallback;
}

/// Font manager — add new fonts by registering [FontOption]s.
class FontService {
  FontService();

  static const defaultFontId = 'noto_sans_arabic';

  final List<FontOption> _fonts = [
    const FontOption(
      id: defaultFontId,
      displayName: 'Default Kurdish',
      family: 'NotoSansArabic',
      assetRegular: 'assets/fonts/NotoSansArabic-Regular.ttf',
      assetBold: 'assets/fonts/NotoSansArabic-Bold.ttf',
    ),
    const FontOption(
      id: 'system_arabic',
      displayName: 'System Arabic',
      family: 'sans-serif',
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
      if (f.family == family) return f;
    }
    return null;
  }

  /// Register a custom font at runtime / Phase 2 custom import hook.
  void register(FontOption option) {
    _fonts.removeWhere((f) => f.id == option.id);
    _fonts.add(option);
  }
}
