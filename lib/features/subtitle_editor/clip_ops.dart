import '../../models/video_clip.dart';

/// Pure helpers for video-clip timeline operations.
class ClipOps {
  ClipOps._();

  static const minDuration = Duration(milliseconds: 200);

  static const filterPresets = <String, String>{
    'none': 'None',
    'vivid': 'Vivid',
    'warm': 'Warm',
    'cool': 'Cool',
    'bw': 'B&W',
    'cinema': 'Cinema',
    'fade': 'Fade film',
    'neon': 'Neon',
  };

  static const transitions = <String, String>{
    'none': 'None',
    'fade': 'Fade',
    'dissolve': 'Dissolve',
    'wipe_left': 'Wipe Left',
    'wipe_right': 'Wipe Right',
    'slide_up': 'Slide Up',
    'zoom': 'Zoom',
    'flash': 'Flash',
  };

  static const aspectRatios = <String, String>{
    '9:16': '9:16 TikTok',
    '16:9': '16:9 YouTube',
    '1:1': '1:1 Square',
    '4:5': '4:5 Feed',
    '21:9': '21:9 Cinema',
    'original': 'Original',
  };

  static List<VideoClip> sorted(List<VideoClip> clips) {
    return [...clips]..sort((a, b) => a.timelineStart.compareTo(b.timelineStart));
  }

  /// Pack clips end-to-end starting at zero (simple CapCut-like layout).
  static List<VideoClip> reflow(List<VideoClip> clips) {
    final list = sorted(clips);
    var cursor = Duration.zero;
    return [
      for (final c in list)
        () {
          final next = c.copyWith(timelineStart: cursor);
          cursor += c.trimmedDuration;
          return next;
        }(),
    ];
  }

  static List<VideoClip> split(List<VideoClip> clips, String id, Duration at) {
    final list = [...clips];
    final i = list.indexWhere((c) => c.id == id);
    if (i < 0) return list;
    final c = list[i];
    if (at <= c.timelineStart || at >= c.timelineEnd) return list;
    final intoTimeline = at - c.timelineStart;
    final intoSource = Duration(
      milliseconds:
          (intoTimeline.inMilliseconds * c.speed.clamp(0.25, 4.0)).round(),
    );
    final splitSource = c.reversed
        ? c.outPoint - intoSource
        : c.inPoint + intoSource;
    if (splitSource <= c.inPoint || splitSource >= c.outPoint) return list;

    final left = c.copyWith(outPoint: splitSource);
    final right = c.duplicateAt(at).copyWith(
          inPoint: splitSource,
          outPoint: c.outPoint,
        );
    list[i] = left;
    list.insert(i + 1, right);
    return reflow(list);
  }

  static List<VideoClip> delete(List<VideoClip> clips, String id) {
    return reflow(clips.where((c) => c.id != id).toList());
  }

  /// Same as delete + reflow (CapCut ripple).
  static List<VideoClip> rippleDelete(List<VideoClip> clips, String id) {
    return delete(clips, id);
  }

  static List<VideoClip> duplicate(List<VideoClip> clips, String id) {
    final list = sorted(clips);
    final i = list.indexWhere((c) => c.id == id);
    if (i < 0) return list;
    final c = list[i];
    list.insert(i + 1, c.duplicateAt(c.timelineEnd));
    return reflow(list);
  }

  static List<VideoClip> trim(
    List<VideoClip> clips,
    String id, {
    Duration? inPoint,
    Duration? outPoint,
  }) {
    final list = [...clips];
    final i = list.indexWhere((c) => c.id == id);
    if (i < 0) return list;
    final c = list[i];
    var nin = inPoint ?? c.inPoint;
    var nout = outPoint ?? c.outPoint;
    if (nin < Duration.zero) nin = Duration.zero;
    if (nout > c.sourceDuration) nout = c.sourceDuration;
    if (nout - nin < minDuration) return list;
    list[i] = c.copyWith(inPoint: nin, outPoint: nout);
    return reflow(list);
  }

  static List<VideoClip> update(
    List<VideoClip> clips,
    String id,
    VideoClip Function(VideoClip) fn,
  ) {
    final list = [...clips];
    final i = list.indexWhere((c) => c.id == id);
    if (i < 0) return list;
    list[i] = fn(list[i]);
    return reflow(list);
  }

  static List<VideoClip> setSpeed(
    List<VideoClip> clips,
    String id,
    double speed,
  ) {
    return update(clips, id, (c) => c.copyWith(speed: speed.clamp(0.25, 4.0)));
  }

  static List<VideoClip> toggleReverse(List<VideoClip> clips, String id) {
    return update(clips, id, (c) => c.copyWith(reversed: !c.reversed));
  }

  /// Insert a short frozen hold by duplicating a 1-frame-ish still region.
  static List<VideoClip> freezeFrame(
    List<VideoClip> clips,
    String id,
    Duration at, {
    Duration hold = const Duration(seconds: 1),
  }) {
    final splitFirst = split(clips, id, at);
    final active = atPosition(splitFirst, at);
    if (active == null) return clips;
    // 250ms source at 0.25x ≈ 1s hold on timeline.
    final frozen = active.copyWith(
      outPoint: active.inPoint + const Duration(milliseconds: 250),
      speed: 0.25,
      fileName: '${active.fileName} (freeze)',
    );
    return update(splitFirst, active.id, (_) => frozen);
  }

  static List<VideoClip> mergeAdjacent(List<VideoClip> clips, String id) {
    final list = sorted(clips);
    final i = list.indexWhere((c) => c.id == id);
    if (i < 0 || i >= list.length - 1) return list;
    final a = list[i];
    final b = list[i + 1];
    if (a.sourcePath != b.sourcePath || a.reversed != b.reversed) return list;
    final gap = a.outPoint - b.inPoint;
    final gapMs = gap.inMilliseconds.abs();
    if (gapMs > 40 && (b.outPoint - a.inPoint).inMilliseconds.abs() > 40) {
      if (a.outPoint != b.inPoint && b.outPoint != a.inPoint) return list;
    }
    final merged = a.copyWith(
      inPoint: a.inPoint < b.inPoint ? a.inPoint : b.inPoint,
      outPoint: a.outPoint > b.outPoint ? a.outPoint : b.outPoint,
    );
    list[i] = merged;
    list.removeAt(i + 1);
    return reflow(list);
  }

  static VideoClip? atPosition(List<VideoClip> clips, Duration position) {
    for (final c in clips) {
      if (position >= c.timelineStart && position < c.timelineEnd) return c;
    }
    return null;
  }

  /// Map timeline position → source media seek time for the active clip.
  static Duration sourceSeek(VideoClip clip, Duration timelinePos) {
    final into = timelinePos - clip.timelineStart;
    final sourceInto = Duration(
      milliseconds: (into.inMilliseconds * clip.speed.clamp(0.25, 4.0)).round(),
    );
    final seek = clip.reversed
        ? clip.outPoint - sourceInto
        : clip.inPoint + sourceInto;
    if (seek < clip.inPoint) return clip.inPoint;
    if (seek > clip.outPoint) return clip.outPoint;
    return seek;
  }
}

