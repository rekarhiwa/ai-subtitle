/// Timestamp conversion helpers for subtitles.
class TimestampUtils {
  TimestampUtils._();

  static Duration fromMilliseconds(int ms) => Duration(milliseconds: ms);

  static int toMilliseconds(Duration d) => d.inMilliseconds;

  /// Formats as `HH:MM:SS,mmm` for SRT.
  static String toSrt(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    final ms = (d.inMilliseconds % 1000).toString().padLeft(3, '0');
    return '$h:$m:$s,$ms';
  }

  /// Formats as `H:MM:SS.cc` for ASS (centiseconds).
  static String toAss(Duration d) {
    final h = d.inHours;
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    final cs = ((d.inMilliseconds % 1000) / 10).floor().toString().padLeft(2, '0');
    return '$h:$m:$s.$cs';
  }

  /// Formats as `MM:SS.mm` for UI lists.
  static String toUi(Duration d) {
    final totalSeconds = d.inMilliseconds / 1000.0;
    final m = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toStringAsFixed(2).padLeft(5, '0');
    return '$m:$s';
  }

  /// Parses UI/editor input like `00:02.40`, `1:02.5`, `00:00:02,400`.
  static Duration? tryParse(String input) {
    final raw = input.trim();
    if (raw.isEmpty) return null;

    final srt = RegExp(r'^(\d{1,2}):(\d{2}):(\d{2})[,.](\d{1,3})$');
    final m1 = srt.firstMatch(raw);
    if (m1 != null) {
      final h = int.parse(m1.group(1)!);
      final m = int.parse(m1.group(2)!);
      final s = int.parse(m1.group(3)!);
      final frac = m1.group(4)!.padRight(3, '0').substring(0, 3);
      return Duration(
        hours: h,
        minutes: m,
        seconds: s,
        milliseconds: int.parse(frac),
      );
    }

    final short = RegExp(r'^(\d{1,3}):(\d{2})(?:[.,](\d{1,3}))?$');
    final m2 = short.firstMatch(raw);
    if (m2 != null) {
      final m = int.parse(m2.group(1)!);
      final s = int.parse(m2.group(2)!);
      final frac = (m2.group(3) ?? '0').padRight(3, '0').substring(0, 3);
      return Duration(minutes: m, seconds: s, milliseconds: int.parse(frac));
    }

    final secondsOnly = double.tryParse(raw);
    if (secondsOnly != null) {
      return Duration(milliseconds: (secondsOnly * 1000).round());
    }
    return null;
  }
}
