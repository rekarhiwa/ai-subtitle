import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import '../../models/audio_clip.dart';
import '../../models/subtitle_segment.dart';
import '../../models/video_clip.dart';
import 'clip_ops.dart';
import 'subtitle_ops.dart';

/// CapCut-style multi-track timeline with a fixed center playhead.
class CaptionTimeline extends StatefulWidget {
  const CaptionTimeline({
    super.key,
    required this.segments,
    required this.position,
    required this.duration,
    required this.activeId,
    required this.onSeek,
    required this.onSelect,
    required this.onSegmentsChanged,
    this.videoClips = const [],
    this.audioClips = const [],
    this.activeClipId,
    this.onSelectClip,
    this.onClipsChanged,
    this.onAddMedia,
    this.thumbnailPath,
    this.height = 168,
  });

  static const minPps = 24.0;
  static const maxPps = 180.0;
  static const rulerH = 20.0;
  static const videoH = 48.0;
  static const captionH = 28.0;
  static const audioH = 28.0;
  static const trackGap = 4.0;

  final List<SubtitleSegment> segments;
  final List<VideoClip> videoClips;
  final List<AudioClip> audioClips;
  final Duration position;
  final Duration duration;
  final String? activeId;
  final String? activeClipId;
  final String? thumbnailPath;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<SubtitleSegment> onSelect;
  final ValueChanged<List<SubtitleSegment>> onSegmentsChanged;
  final ValueChanged<VideoClip>? onSelectClip;
  final ValueChanged<List<VideoClip>>? onClipsChanged;
  final VoidCallback? onAddMedia;
  final double height;

  @override
  State<CaptionTimeline> createState() => _CaptionTimelineState();
}

class _CaptionTimelineState extends State<CaptionTimeline> {
  final _scroll = ScrollController();
  double _pps = 56;
  double _scaleStartPps = 56;
  bool _userScrolling = false;
  bool _programmaticScroll = false;
  double _sidePad = 180;

  double get _contentSecs =>
      (widget.duration.inMilliseconds / 1000.0).clamp(0.1, 86400.0);

  double get _trackWidth => _contentSecs * _pps;

  double get _totalWidth => _trackWidth + _sidePad * 2;

  double _xFor(Duration d) =>
      _sidePad + (d.inMilliseconds / 1000.0) * _pps;

  Duration _timeForContentX(double contentX) {
    final secs = ((contentX - _sidePad) / _pps).clamp(0.0, _contentSecs);
    return Duration(milliseconds: (secs * 1000).round());
  }

  Duration _timeAtViewportCenter() {
    if (!_scroll.hasClients) return widget.position;
    final centerX = _scroll.offset + _scroll.position.viewportDimension / 2;
    return _timeForContentX(centerX);
  }

  double _offsetForTime(Duration d) {
    if (!_scroll.hasClients) return 0;
    final vp = _scroll.position.viewportDimension;
    final target = _xFor(d) - vp / 2;
    return target.clamp(0.0, _scroll.position.maxScrollExtent);
  }

  void _syncScrollToPosition() {
    if (!_scroll.hasClients || _userScrolling) return;
    final next = _offsetForTime(widget.position);
    if ((next - _scroll.offset).abs() < 0.5) return;
    _programmaticScroll = true;
    _scroll.jumpTo(next);
    _programmaticScroll = false;
  }

  void _seekFromScroll() {
    if (_programmaticScroll || !_scroll.hasClients) return;
    widget.onSeek(_timeAtViewportCenter());
  }

  void _zoomTo(double next) {
    next = next.clamp(CaptionTimeline.minPps, CaptionTimeline.maxPps);
    if ((next - _pps).abs() < 0.4) return;
    final timeUnderCenter = _timeAtViewportCenter();
    setState(() => _pps = next);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _programmaticScroll = true;
      _scroll.jumpTo(_offsetForTime(timeUnderCenter));
      _programmaticScroll = false;
    });
  }

  void _updateSidePad() {
    final vp = MediaQuery.sizeOf(context).width;
    final next = vp / 2;
    if ((next - _sidePad).abs() > 1) {
      setState(() => _sidePad = next);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncScrollToPosition();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateSidePad();
  }

  @override
  void didUpdateWidget(covariant CaptionTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.position != widget.position ||
        oldWidget.duration != widget.duration) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncScrollToPosition();
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sorted = SubtitleOps.sorted(widget.segments);
    final thumbOk = widget.thumbnailPath != null &&
        File(widget.thumbnailPath!).existsSync();

    const videoTop = CaptionTimeline.rulerH + 2;
    const captionTop =
        videoTop + CaptionTimeline.videoH + CaptionTimeline.trackGap;
    const audioTop =
        captionTop + CaptionTimeline.captionH + CaptionTimeline.trackGap;

    return Container(
      height: widget.height,
      color: const Color(0xFF000000),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final vp = constraints.maxWidth;
          if ((vp / 2 - _sidePad).abs() > 1) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _sidePad = vp / 2);
            });
          }

          return GestureDetector(
            onScaleStart: (_) => _scaleStartPps = _pps,
            onScaleUpdate: (d) {
              if (d.pointerCount >= 2) _zoomTo(_scaleStartPps * d.scale);
            },
            child: Stack(
              children: [
                NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    if (n is ScrollStartNotification &&
                        n.dragDetails != null) {
                      _userScrolling = true;
                    }
                    if (n is ScrollUpdateNotification && _userScrolling) {
                      _seekFromScroll();
                    }
                    if (n is ScrollEndNotification) {
                      _userScrolling = false;
                      _seekFromScroll();
                    }
                    return false;
                  },
                  child: SingleChildScrollView(
                    controller: _scroll,
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: SizedBox(
                      width: _totalWidth,
                      height: widget.height,
                      child: Stack(
                        children: [
                          Positioned(
                            left: 0,
                            right: 0,
                            top: 0,
                            height: CaptionTimeline.rulerH,
                            child: CustomPaint(
                              painter: _RulerPainter(
                                pps: _pps,
                                sidePad: _sidePad,
                                duration: widget.duration,
                              ),
                            ),
                          ),
                          // Video bed
                          Positioned(
                            left: _sidePad,
                            width: _trackWidth,
                            top: videoTop,
                            height: CaptionTimeline.videoH,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: _Filmstrip(
                                width: _trackWidth,
                                thumbnailPath:
                                    thumbOk ? widget.thumbnailPath : null,
                                pps: _pps,
                              ),
                            ),
                          ),
                          // Caption bed
                          Positioned(
                            left: _sidePad,
                            width: _trackWidth,
                            top: captionTop,
                            height: CaptionTimeline.captionH,
                            child: Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFF121212),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                          // Audio bed
                          Positioned(
                            left: _sidePad,
                            width: _trackWidth,
                            top: audioTop,
                            height: CaptionTimeline.audioH,
                            child: Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFF121212),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                          for (final a in widget.audioClips)
                            Positioned(
                              left: _xFor(a.timelineStart),
                              width: (_xFor(a.timelineEnd) -
                                      _xFor(a.timelineStart))
                                  .clamp(12.0, _totalWidth),
                              top: audioTop,
                              height: CaptionTimeline.audioH,
                              child: _AudioBlock(
                                label: a.fileName.isEmpty
                                    ? 'Audio'
                                    : a.fileName,
                                selected: false,
                              ),
                            ),
                          for (final clip
                              in ClipOps.sorted(widget.videoClips))
                            Positioned(
                              left: _xFor(clip.timelineStart),
                              width: (_xFor(clip.timelineEnd) -
                                      _xFor(clip.timelineStart))
                                  .clamp(12.0, _totalWidth),
                              top: videoTop,
                              height: CaptionTimeline.videoH,
                              child: _SelectableClipFrame(
                                selected: clip.id == widget.activeClipId,
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  widget.onSelectClip?.call(clip);
                                },
                              ),
                            ),
                          // + at end of video
                          if (widget.onAddMedia != null)
                            Positioned(
                              left: _sidePad + _trackWidth + 6,
                              top: videoTop +
                                  (CaptionTimeline.videoH - 28) / 2,
                              child: GestureDetector(
                                onTap: widget.onAddMedia,
                                child: Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF2A2A2A),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: const Color(0xFF4A4A4A),
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.add,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          for (final s in sorted)
                            _TimelineClip(
                              key: ValueKey(s.id),
                              segment: s,
                              selected: s.id == widget.activeId,
                              left: _xFor(s.start),
                              width: (_xFor(s.end) - _xFor(s.start))
                                  .clamp(18.0, _totalWidth),
                              top: captionTop,
                              height: CaptionTimeline.captionH,
                              pps: _pps,
                              sidePad: _sidePad,
                              mediaDuration: widget.duration,
                              onSelect: () {
                                HapticFeedback.selectionClick();
                                widget.onSelect(s);
                              },
                              onChanged: (updated) {
                                final next = widget.segments
                                    .map((e) =>
                                        e.id == updated.id ? updated : e)
                                    .toList();
                                widget.onSegmentsChanged(
                                  SubtitleOps.resizeSegment(
                                    next,
                                    updated.id,
                                    start: updated.start,
                                    end: updated.end,
                                    mediaDuration: widget.duration,
                                  ),
                                );
                              },
                            ),
                          if (sorted.isEmpty)
                            Positioned(
                              left: _sidePad + 10,
                              top: captionTop + 6,
                              child: const Text(
                                'Captions',
                                style: TextStyle(
                                  color: Color(0xFF3A3A3A),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Fixed center playhead (CapCut white)
                IgnorePointer(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      width: 12,
                      height: widget.height,
                      child: Column(
                        children: [
                          CustomPaint(
                            size: const Size(10, 6),
                            painter: _PlayheadTrianglePainter(),
                          ),
                          Expanded(
                            child: Center(
                              child: Container(
                                width: 1.5,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Filmstrip extends StatelessWidget {
  const _Filmstrip({
    required this.width,
    required this.thumbnailPath,
    required this.pps,
  });

  final double width;
  final String? thumbnailPath;
  final double pps;

  @override
  Widget build(BuildContext context) {
    const cell = 48.0;
    final count = (width / cell).ceil().clamp(1, 400);
    return ColoredBox(
      color: AppColors.filmstrip,
      child: Row(
        children: List.generate(count, (i) {
          return SizedBox(
            width: cell,
            height: CaptionTimeline.videoH,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (thumbnailPath != null)
                  Image.file(
                    File(thumbnailPath!),
                    fit: BoxFit.cover,
                    opacity: const AlwaysStoppedAnimation(0.9),
                  )
                else
                  Container(color: AppColors.timelineVideo),
                const Align(
                  alignment: Alignment.centerRight,
                  child: VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: Colors.black45,
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

class _AudioBlock extends StatelessWidget {
  const _AudioBlock({required this.label, required this.selected});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E88E5),
        borderRadius: BorderRadius.circular(3),
        border: selected
            ? Border.all(color: Colors.white, width: 1.5)
            : null,
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(painter: _WaveformPainter()),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          if (selected) ...[
            const _EdgeHandleBar(left: true),
            const _EdgeHandleBar(left: false),
          ],
        ],
      ),
    );
  }
}

class _SelectableClipFrame extends StatelessWidget {
  const _SelectableClipFrame({
    required this.selected,
    required this.onTap,
  });

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: selected ? Colors.white : Colors.white24,
            width: selected ? 2 : 0.8,
          ),
        ),
        child: selected
            ? const Stack(
                children: [
                  _EdgeHandleBar(left: true),
                  _EdgeHandleBar(left: false),
                ],
              )
            : null,
      ),
    );
  }
}

class _EdgeHandleBar extends StatelessWidget {
  const _EdgeHandleBar({required this.left});

  final bool left;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left ? 0 : null,
      right: left ? null : 0,
      top: 0,
      bottom: 0,
      width: 8,
      child: ColoredBox(
        color: Colors.white,
        child: Center(
          child: Container(
            width: 2,
            height: 14,
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ),
      ),
    );
  }
}

class _TimelineClip extends StatefulWidget {
  const _TimelineClip({
    super.key,
    required this.segment,
    required this.selected,
    required this.left,
    required this.width,
    required this.top,
    required this.height,
    required this.pps,
    required this.sidePad,
    required this.mediaDuration,
    required this.onSelect,
    required this.onChanged,
  });

  final SubtitleSegment segment;
  final bool selected;
  final double left;
  final double width;
  final double top;
  final double height;
  final double pps;
  final double sidePad;
  final Duration mediaDuration;
  final VoidCallback onSelect;
  final ValueChanged<SubtitleSegment> onChanged;

  @override
  State<_TimelineClip> createState() => _TimelineClipState();
}

class _TimelineClipState extends State<_TimelineClip> {
  Duration? _dragStart;
  Duration? _dragEnd;

  Duration get _start => _dragStart ?? widget.segment.start;
  Duration get _end => _dragEnd ?? widget.segment.end;

  double get _left =>
      widget.sidePad + (_start.inMilliseconds / 1000.0) * widget.pps;
  double get _w =>
      (((_end - _start).inMilliseconds / 1000.0) * widget.pps)
          .clamp(18.0, 100000.0);

  void _commit() {
    if (_dragStart == null && _dragEnd == null) return;
    widget.onChanged(widget.segment.copyWith(start: _start, end: _end));
    _dragStart = null;
    _dragEnd = null;
  }

  @override
  Widget build(BuildContext context) {
    final dragging = _dragStart != null || _dragEnd != null;
    return Positioned(
      left: dragging ? _left : widget.left,
      width: dragging ? _w : widget.width,
      top: widget.top,
      height: widget.height,
      child: GestureDetector(
        onTap: widget.onSelect,
        onHorizontalDragStart: (_) {
          widget.onSelect();
          _dragStart = widget.segment.start;
          _dragEnd = widget.segment.end;
        },
        onHorizontalDragUpdate: (d) {
          final delta =
              Duration(milliseconds: (d.delta.dx / widget.pps * 1000).round());
          setState(() {
            var ns = _start + delta;
            var ne = _end + delta;
            final dur = ne - ns;
            if (ns < Duration.zero) {
              ns = Duration.zero;
              ne = dur;
            }
            if (ne > widget.mediaDuration) {
              ne = widget.mediaDuration;
              ns = ne - dur;
              if (ns < Duration.zero) ns = Duration.zero;
            }
            _dragStart = ns;
            _dragEnd = ne;
          });
        },
        onHorizontalDragEnd: (_) => _commit(),
        child: Container(
          decoration: BoxDecoration(
            color: widget.selected
                ? AppColors.timelineClipActive
                : AppColors.timelineClip,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(
              color: widget.selected ? Colors.white : Colors.transparent,
              width: widget.selected ? 1.5 : 0,
            ),
          ),
          child: Stack(
            children: [
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: widget.selected ? 10 : 6,
                ),
                child: Center(
                  child: Text(
                    widget.segment.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textDirection: TextDirection.rtl,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: widget.selected ? Colors.black : Colors.white,
                    ),
                  ),
                ),
              ),
              if (widget.selected) ...[
                _resizeHandle(
                  left: true,
                  onUpdate: (dx) {
                    final deltaMs = (dx / widget.pps * 1000).round();
                    setState(() {
                      var ns = _start + Duration(milliseconds: deltaMs);
                      if (ns < Duration.zero) ns = Duration.zero;
                      if (_end - ns < SubtitleOps.minDuration) {
                        ns = _end - SubtitleOps.minDuration;
                      }
                      _dragStart = ns;
                      _dragEnd ??= widget.segment.end;
                    });
                  },
                ),
                _resizeHandle(
                  left: false,
                  onUpdate: (dx) {
                    final deltaMs = (dx / widget.pps * 1000).round();
                    setState(() {
                      var ne = _end + Duration(milliseconds: deltaMs);
                      if (ne > widget.mediaDuration) {
                        ne = widget.mediaDuration;
                      }
                      if (ne - _start < SubtitleOps.minDuration) {
                        ne = _start + SubtitleOps.minDuration;
                      }
                      _dragEnd = ne;
                      _dragStart ??= widget.segment.start;
                    });
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _resizeHandle({
    required bool left,
    required void Function(double dx) onUpdate,
  }) {
    return Positioned(
      left: left ? 0 : null,
      right: left ? null : 0,
      top: 0,
      bottom: 0,
      width: 8,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) {
          widget.onSelect();
          _dragStart = widget.segment.start;
          _dragEnd = widget.segment.end;
        },
        onHorizontalDragUpdate: (d) => onUpdate(d.delta.dx),
        onHorizontalDragEnd: (_) => _commit(),
        child: ColoredBox(
          color: Colors.white,
          child: Center(
            child: Container(
              width: 2,
              height: 12,
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayheadTrianglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _WaveformPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    final mid = size.height / 2;
    final path = Path()..moveTo(0, mid);
    final rng = math.Random(7);
    for (var x = 0.0; x < size.width; x += 3) {
      final amp = (rng.nextDouble() * 0.7 + 0.15) * mid * 0.85;
      path.lineTo(x, mid - amp);
      path.moveTo(x, mid + amp);
      path.lineTo(x, mid - amp);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _RulerPainter extends CustomPainter {
  _RulerPainter({
    required this.pps,
    required this.sidePad,
    required this.duration,
  });

  final double pps;
  final double sidePad;
  final Duration duration;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF3A3A3A)
      ..strokeWidth = 1;
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    final totalSec = duration.inMilliseconds / 1000.0;
    final step = pps >= 80
        ? 1
        : pps >= 45
            ? 2
            : pps >= 28
                ? 5
                : 10;

    for (var s = 0; s <= totalSec.ceil(); s += step) {
      final x = sidePad + s * pps;
      final major = s % (step == 1 ? 5 : step * 2) == 0;
      canvas.drawLine(
        Offset(x, major ? size.height - 9 : size.height - 4),
        Offset(x, size.height),
        paint,
      );
      if (major) {
        final m = s ~/ 60;
        final sec = s % 60;
        textPainter.text = TextSpan(
          text:
              '${m.toString().padLeft(1, '0')}:${sec.toString().padLeft(2, '0')}',
          style: const TextStyle(
            color: Color(0xFF6B6B6B),
            fontSize: 9,
            fontWeight: FontWeight.w500,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        );
        textPainter.layout();
        textPainter.paint(canvas, Offset(x + 3, 1));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RulerPainter oldDelegate) =>
      oldDelegate.pps != pps ||
      oldDelegate.duration != duration ||
      oldDelegate.sidePad != sidePad;
}
