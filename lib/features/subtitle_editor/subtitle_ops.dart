import 'package:uuid/uuid.dart';

import '../../models/subtitle_segment.dart';

class SubtitleOps {
  SubtitleOps._();

  static const minDuration = Duration(milliseconds: 200);

  static List<SubtitleSegment> sorted(List<SubtitleSegment> segments) {
    return [...segments]..sort((a, b) => a.start.compareTo(b.start));
  }

  static List<SubtitleSegment> split(
    List<SubtitleSegment> segments,
    String id, {
    Duration? at,
  }) {
    final result = [...segments];
    final index = result.indexWhere((s) => s.id == id);
    if (index < 0) return result;
    final segment = result[index];
    final splitAt = at ??
        Duration(
          milliseconds:
              (segment.start.inMilliseconds + segment.end.inMilliseconds) ~/ 2,
        );
    if (splitAt <= segment.start || splitAt >= segment.end) return result;

    final text = segment.text.trim();
    final mid = (text.length / 2).floor();
    var leftText = text;
    var rightText = text;
    final space = text.lastIndexOf(' ', mid);
    if (space > 0) {
      leftText = text.substring(0, space).trim();
      rightText = text.substring(space + 1).trim();
    } else if (text.length > 1) {
      leftText = text.substring(0, mid).trim();
      rightText = text.substring(mid).trim();
    }
    if (leftText.isEmpty) leftText = text;
    if (rightText.isEmpty) rightText = text;

    result[index] = segment.copyWith(end: splitAt, text: leftText);
    result.insert(
      index + 1,
      SubtitleSegment(
        id: const Uuid().v4(),
        start: splitAt,
        end: segment.end,
        text: rightText,
      ),
    );
    return sorted(result);
  }

  static List<SubtitleSegment> merge(
    List<SubtitleSegment> segments,
    String firstId,
    String secondId,
  ) {
    final result = sorted(segments);
    final aIndex = result.indexWhere((s) => s.id == firstId);
    final bIndex = result.indexWhere((s) => s.id == secondId);
    if (aIndex < 0 || bIndex < 0 || aIndex == bIndex) return result;

    final low = aIndex < bIndex ? aIndex : bIndex;
    final high = aIndex < bIndex ? bIndex : aIndex;
    if (high != low + 1) {
      return result;
    }

    final a = result[low];
    final b = result[high];
    final merged = a.copyWith(
      end: a.end > b.end ? a.end : b.end,
      text: '${a.text.trim()} ${b.text.trim()}'.trim(),
    );
    result[low] = merged;
    result.removeAt(high);
    return result;
  }

  static List<SubtitleSegment> delete(
    List<SubtitleSegment> segments,
    String id,
  ) {
    return segments.where((s) => s.id != id).toList();
  }

  static List<SubtitleSegment> add(
    List<SubtitleSegment> segments, {
    required Duration start,
    required Duration end,
    required String text,
  }) {
    return sorted([
      ...segments,
      SubtitleSegment.create(start: start, end: end, text: text),
    ]);
  }

  static SubtitleSegment? activeAt(
    List<SubtitleSegment> segments,
    Duration position,
  ) {
    for (final s in segments) {
      if (s.contains(position)) return s;
    }
    return null;
  }

  /// Move a segment by [delta], clamped to [0, mediaDuration].
  static List<SubtitleSegment> moveSegment(
    List<SubtitleSegment> segments,
    String id,
    Duration delta, {
    Duration mediaDuration = const Duration(hours: 24),
  }) {
    final result = [...segments];
    final index = result.indexWhere((s) => s.id == id);
    if (index < 0) return result;
    final segment = result[index];
    final dur = segment.duration;
    var newStart = segment.start + delta;
    if (newStart < Duration.zero) newStart = Duration.zero;
    var newEnd = newStart + dur;
    if (newEnd > mediaDuration) {
      newEnd = mediaDuration;
      newStart = newEnd - dur;
      if (newStart < Duration.zero) newStart = Duration.zero;
    }
    if (newEnd - newStart < minDuration) return result;
    result[index] = segment.copyWith(start: newStart, end: newEnd);
    return sorted(_lightenOverlaps(result, id));
  }

  /// Resize start and/or end edges with a minimum duration.
  static List<SubtitleSegment> resizeSegment(
    List<SubtitleSegment> segments,
    String id, {
    Duration? start,
    Duration? end,
    Duration mediaDuration = const Duration(hours: 24),
  }) {
    final result = [...segments];
    final index = result.indexWhere((s) => s.id == id);
    if (index < 0) return result;
    final segment = result[index];

    var newStart = start ?? segment.start;
    var newEnd = end ?? segment.end;
    if (newStart < Duration.zero) newStart = Duration.zero;
    if (newEnd > mediaDuration) newEnd = mediaDuration;
    if (newEnd - newStart < minDuration) {
      if (start != null && end == null) {
        newStart = newEnd - minDuration;
      } else if (end != null && start == null) {
        newEnd = newStart + minDuration;
      } else {
        return result;
      }
      if (newStart < Duration.zero) {
        newStart = Duration.zero;
        newEnd = minDuration;
      }
      if (newEnd > mediaDuration) {
        newEnd = mediaDuration;
        newStart = mediaDuration - minDuration;
        if (newStart < Duration.zero) newStart = Duration.zero;
      }
    }

    result[index] = segment.copyWith(start: newStart, end: newEnd);
    return sorted(_lightenOverlaps(result, id));
  }

  /// Nudge neighbors slightly if they fully collide with [movedId].
  static List<SubtitleSegment> _lightenOverlaps(
    List<SubtitleSegment> segments,
    String movedId,
  ) {
    final list = sorted(segments);
    final i = list.indexWhere((s) => s.id == movedId);
    if (i < 0) return list;
    final moved = list[i];

    if (i > 0) {
      final prev = list[i - 1];
      if (prev.end > moved.start) {
        final clampedEnd = moved.start;
        if (clampedEnd - prev.start >= minDuration) {
          list[i - 1] = prev.copyWith(end: clampedEnd);
        }
      }
    }
    if (i < list.length - 1) {
      final next = list[i + 1];
      if (next.start < moved.end) {
        final clampedStart = moved.end;
        if (next.end - clampedStart >= minDuration) {
          list[i + 1] = next.copyWith(start: clampedStart);
        }
      }
    }
    return list;
  }
}
