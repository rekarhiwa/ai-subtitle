import 'package:uuid/uuid.dart';

/// A trimmed segment of a source video placed on the timeline.
class VideoClip {
  const VideoClip({
    required this.id,
    required this.sourcePath,
    required this.sourceDuration,
    required this.inPoint,
    required this.outPoint,
    required this.timelineStart,
    this.thumbnailPath,
    this.fileName = '',
    this.speed = 1.0,
    this.reversed = false,
    this.volume = 1.0,
    this.opacity = 1.0,
    this.rotationDeg = 0,
    this.flipH = false,
    this.flipV = false,
    this.cropLeft = 0,
    this.cropTop = 0,
    this.cropRight = 0,
    this.cropBottom = 0,
    this.fadeInMs = 0,
    this.fadeOutMs = 0,
    this.filterId = 'none',
    this.brightness = 0,
    this.contrast = 0,
    this.saturation = 0,
    this.vignette = 0,
    this.grain = 0,
    this.transitionOut = 'none',
    this.zoom = 1.0,
    this.panX = 0.0,
    this.panY = 0.0,
    this.hue = 0.0,
    this.blendMode = 'normal',
    this.effectId = 'none',
    this.isOverlay = false,
    this.overlayX = 0.7,
    this.overlayY = 0.2,
    this.overlayScale = 0.35,
    this.maskType = 'none',
    this.chromaKey = false,
    this.chromaSimilarity = 0.3,
    this.stabilize = false,
    this.cameraFx = 'none',
    this.beauty = 0.0,
  });

  final String id;
  final String sourcePath;
  final Duration sourceDuration;
  final Duration inPoint;
  final Duration outPoint;
  final Duration timelineStart;
  final String? thumbnailPath;
  final String fileName;

  /// Playback / export speed (0.25–4.0).
  final double speed;
  final bool reversed;
  final double volume;
  final double opacity;
  final double rotationDeg;
  final bool flipH;
  final bool flipV;

  /// Normalized crop insets 0–0.45.
  final double cropLeft;
  final double cropTop;
  final double cropRight;
  final double cropBottom;
  final int fadeInMs;
  final int fadeOutMs;
  final String filterId;

  /// -1..1 style adjust.
  final double brightness;
  final double contrast;
  final double saturation;
  final double vignette;
  final double grain;
  final String transitionOut;
  final double zoom;
  final double panX;
  final double panY;
  final double hue;
  final String blendMode;
  final String effectId;
  final bool isOverlay;
  final double overlayX;
  final double overlayY;
  final double overlayScale;
  final String maskType;
  final bool chromaKey;
  final double chromaSimilarity;
  final bool stabilize;
  final String cameraFx;
  final double beauty;

  Duration get rawTrimmed {
    final d = outPoint - inPoint;
    return d.isNegative ? Duration.zero : d;
  }

  /// Timeline duration after speed.
  Duration get trimmedDuration {
    final ms = (rawTrimmed.inMilliseconds / speed.clamp(0.25, 4.0)).round();
    return Duration(milliseconds: ms < 1 ? 1 : ms);
  }

  Duration get timelineEnd => timelineStart + trimmedDuration;

  factory VideoClip.create({
    required String sourcePath,
    required Duration sourceDuration,
    required Duration timelineStart,
    Duration? inPoint,
    Duration? outPoint,
    String? thumbnailPath,
    String fileName = '',
    double speed = 1.0,
    bool reversed = false,
    double volume = 1.0,
    double opacity = 1.0,
    double rotationDeg = 0,
    bool flipH = false,
    bool flipV = false,
    double cropLeft = 0,
    double cropTop = 0,
    double cropRight = 0,
    double cropBottom = 0,
    int fadeInMs = 0,
    int fadeOutMs = 0,
    String filterId = 'none',
    double brightness = 0,
    double contrast = 0,
    double saturation = 0,
    double vignette = 0,
    double grain = 0,
    String transitionOut = 'none',
    double zoom = 1.0,
    double panX = 0.0,
    double panY = 0.0,
    double hue = 0.0,
    String blendMode = 'normal',
    String effectId = 'none',
    bool isOverlay = false,
    double overlayX = 0.7,
    double overlayY = 0.2,
    double overlayScale = 0.35,
    String maskType = 'none',
    bool chromaKey = false,
    double chromaSimilarity = 0.3,
    bool stabilize = false,
    String cameraFx = 'none',
    double beauty = 0.0,
  }) {
    return VideoClip(
      id: const Uuid().v4(),
      sourcePath: sourcePath,
      sourceDuration: sourceDuration,
      inPoint: inPoint ?? Duration.zero,
      outPoint: outPoint ?? sourceDuration,
      timelineStart: timelineStart,
      thumbnailPath: thumbnailPath,
      fileName: fileName,
      speed: speed,
      reversed: reversed,
      volume: volume,
      opacity: opacity,
      rotationDeg: rotationDeg,
      flipH: flipH,
      flipV: flipV,
      cropLeft: cropLeft,
      cropTop: cropTop,
      cropRight: cropRight,
      cropBottom: cropBottom,
      fadeInMs: fadeInMs,
      fadeOutMs: fadeOutMs,
      filterId: filterId,
      brightness: brightness,
      contrast: contrast,
      saturation: saturation,
      vignette: vignette,
      grain: grain,
      transitionOut: transitionOut,
      zoom: zoom,
      panX: panX,
      panY: panY,
      hue: hue,
      blendMode: blendMode,
      effectId: effectId,
      isOverlay: isOverlay,
      overlayX: overlayX,
      overlayY: overlayY,
      overlayScale: overlayScale,
      maskType: maskType,
      chromaKey: chromaKey,
      chromaSimilarity: chromaSimilarity,
      stabilize: stabilize,
      cameraFx: cameraFx,
      beauty: beauty,
    );
  }

  factory VideoClip.fromJson(Map<String, dynamic> json) {
    return VideoClip(
      id: json['id'] as String,
      sourcePath: json['sourcePath'] as String,
      sourceDuration: Duration(milliseconds: json['sourceDurationMs'] as int),
      inPoint: Duration(milliseconds: json['inPointMs'] as int),
      outPoint: Duration(milliseconds: json['outPointMs'] as int),
      timelineStart: Duration(milliseconds: json['timelineStartMs'] as int),
      thumbnailPath: json['thumbnailPath'] as String?,
      fileName: (json['fileName'] as String?) ?? '',
      speed: (json['speed'] as num?)?.toDouble() ?? 1.0,
      reversed: json['reversed'] as bool? ?? false,
      volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
      rotationDeg: (json['rotationDeg'] as num?)?.toDouble() ?? 0,
      flipH: json['flipH'] as bool? ?? false,
      flipV: json['flipV'] as bool? ?? false,
      cropLeft: (json['cropLeft'] as num?)?.toDouble() ?? 0,
      cropTop: (json['cropTop'] as num?)?.toDouble() ?? 0,
      cropRight: (json['cropRight'] as num?)?.toDouble() ?? 0,
      cropBottom: (json['cropBottom'] as num?)?.toDouble() ?? 0,
      fadeInMs: json['fadeInMs'] as int? ?? 0,
      fadeOutMs: json['fadeOutMs'] as int? ?? 0,
      filterId: json['filterId'] as String? ?? 'none',
      brightness: (json['brightness'] as num?)?.toDouble() ?? 0,
      contrast: (json['contrast'] as num?)?.toDouble() ?? 0,
      saturation: (json['saturation'] as num?)?.toDouble() ?? 0,
      vignette: (json['vignette'] as num?)?.toDouble() ?? 0,
      grain: (json['grain'] as num?)?.toDouble() ?? 0,
      transitionOut: json['transitionOut'] as String? ?? 'none',
      zoom: (json['zoom'] as num?)?.toDouble() ?? 1.0,
      panX: (json['panX'] as num?)?.toDouble() ?? 0.0,
      panY: (json['panY'] as num?)?.toDouble() ?? 0.0,
      hue: (json['hue'] as num?)?.toDouble() ?? 0.0,
      blendMode: json['blendMode'] as String? ?? 'normal',
      effectId: json['effectId'] as String? ?? 'none',
      isOverlay: json['isOverlay'] as bool? ?? false,
      overlayX: (json['overlayX'] as num?)?.toDouble() ?? 0.7,
      overlayY: (json['overlayY'] as num?)?.toDouble() ?? 0.2,
      overlayScale: (json['overlayScale'] as num?)?.toDouble() ?? 0.35,
      maskType: json['maskType'] as String? ?? 'none',
      chromaKey: json['chromaKey'] as bool? ?? false,
      chromaSimilarity: (json['chromaSimilarity'] as num?)?.toDouble() ?? 0.3,
      stabilize: json['stabilize'] as bool? ?? false,
      cameraFx: json['cameraFx'] as String? ?? 'none',
      beauty: (json['beauty'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'sourcePath': sourcePath,
        'sourceDurationMs': sourceDuration.inMilliseconds,
        'inPointMs': inPoint.inMilliseconds,
        'outPointMs': outPoint.inMilliseconds,
        'timelineStartMs': timelineStart.inMilliseconds,
        'thumbnailPath': thumbnailPath,
        'fileName': fileName,
        'speed': speed,
        'reversed': reversed,
        'volume': volume,
        'opacity': opacity,
        'rotationDeg': rotationDeg,
        'flipH': flipH,
        'flipV': flipV,
        'cropLeft': cropLeft,
        'cropTop': cropTop,
        'cropRight': cropRight,
        'cropBottom': cropBottom,
        'fadeInMs': fadeInMs,
        'fadeOutMs': fadeOutMs,
        'filterId': filterId,
        'brightness': brightness,
        'contrast': contrast,
        'saturation': saturation,
        'vignette': vignette,
        'grain': grain,
        'transitionOut': transitionOut,
        'zoom': zoom,
        'panX': panX,
        'panY': panY,
        'hue': hue,
        'blendMode': blendMode,
        'effectId': effectId,
        'isOverlay': isOverlay,
        'overlayX': overlayX,
        'overlayY': overlayY,
        'overlayScale': overlayScale,
        'maskType': maskType,
        'chromaKey': chromaKey,
        'chromaSimilarity': chromaSimilarity,
        'stabilize': stabilize,
        'cameraFx': cameraFx,
        'beauty': beauty,
      };

  VideoClip copyWith({
    String? id,
    String? sourcePath,
    Duration? sourceDuration,
    Duration? inPoint,
    Duration? outPoint,
    Duration? timelineStart,
    String? thumbnailPath,
    String? fileName,
    double? speed,
    bool? reversed,
    double? volume,
    double? opacity,
    double? rotationDeg,
    bool? flipH,
    bool? flipV,
    double? cropLeft,
    double? cropTop,
    double? cropRight,
    double? cropBottom,
    int? fadeInMs,
    int? fadeOutMs,
    String? filterId,
    double? brightness,
    double? contrast,
    double? saturation,
    double? vignette,
    double? grain,
    String? transitionOut,
    double? zoom,
    double? panX,
    double? panY,
    double? hue,
    String? blendMode,
    String? effectId,
    bool? isOverlay,
    double? overlayX,
    double? overlayY,
    double? overlayScale,
    String? maskType,
    bool? chromaKey,
    double? chromaSimilarity,
    bool? stabilize,
    String? cameraFx,
    double? beauty,
  }) {
    return VideoClip(
      id: id ?? this.id,
      sourcePath: sourcePath ?? this.sourcePath,
      sourceDuration: sourceDuration ?? this.sourceDuration,
      inPoint: inPoint ?? this.inPoint,
      outPoint: outPoint ?? this.outPoint,
      timelineStart: timelineStart ?? this.timelineStart,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      fileName: fileName ?? this.fileName,
      speed: speed ?? this.speed,
      reversed: reversed ?? this.reversed,
      volume: volume ?? this.volume,
      opacity: opacity ?? this.opacity,
      rotationDeg: rotationDeg ?? this.rotationDeg,
      flipH: flipH ?? this.flipH,
      flipV: flipV ?? this.flipV,
      cropLeft: cropLeft ?? this.cropLeft,
      cropTop: cropTop ?? this.cropTop,
      cropRight: cropRight ?? this.cropRight,
      cropBottom: cropBottom ?? this.cropBottom,
      fadeInMs: fadeInMs ?? this.fadeInMs,
      fadeOutMs: fadeOutMs ?? this.fadeOutMs,
      filterId: filterId ?? this.filterId,
      brightness: brightness ?? this.brightness,
      contrast: contrast ?? this.contrast,
      saturation: saturation ?? this.saturation,
      vignette: vignette ?? this.vignette,
      grain: grain ?? this.grain,
      transitionOut: transitionOut ?? this.transitionOut,
      zoom: zoom ?? this.zoom,
      panX: panX ?? this.panX,
      panY: panY ?? this.panY,
      hue: hue ?? this.hue,
      blendMode: blendMode ?? this.blendMode,
      effectId: effectId ?? this.effectId,
      isOverlay: isOverlay ?? this.isOverlay,
      overlayX: overlayX ?? this.overlayX,
      overlayY: overlayY ?? this.overlayY,
      overlayScale: overlayScale ?? this.overlayScale,
      maskType: maskType ?? this.maskType,
      chromaKey: chromaKey ?? this.chromaKey,
      chromaSimilarity: chromaSimilarity ?? this.chromaSimilarity,
      stabilize: stabilize ?? this.stabilize,
      cameraFx: cameraFx ?? this.cameraFx,
      beauty: beauty ?? this.beauty,
    );
  }

  /// Copy effects onto a new identity (for duplicate).
  VideoClip duplicateAt(Duration timelineStart) {
    return VideoClip.create(
      sourcePath: sourcePath,
      sourceDuration: sourceDuration,
      timelineStart: timelineStart,
      inPoint: inPoint,
      outPoint: outPoint,
      thumbnailPath: thumbnailPath,
      fileName: fileName,
      speed: speed,
      reversed: reversed,
      volume: volume,
      opacity: opacity,
      rotationDeg: rotationDeg,
      flipH: flipH,
      flipV: flipV,
      cropLeft: cropLeft,
      cropTop: cropTop,
      cropRight: cropRight,
      cropBottom: cropBottom,
      fadeInMs: fadeInMs,
      fadeOutMs: fadeOutMs,
      filterId: filterId,
      brightness: brightness,
      contrast: contrast,
      saturation: saturation,
      vignette: vignette,
      grain: grain,
      transitionOut: transitionOut,
      zoom: zoom,
      panX: panX,
      panY: panY,
      hue: hue,
      blendMode: blendMode,
      effectId: effectId,
      isOverlay: isOverlay,
      overlayX: overlayX,
      overlayY: overlayY,
      overlayScale: overlayScale,
      maskType: maskType,
      chromaKey: chromaKey,
      chromaSimilarity: chromaSimilarity,
      stabilize: stabilize,
      cameraFx: cameraFx,
      beauty: beauty,
    );
  }
}
