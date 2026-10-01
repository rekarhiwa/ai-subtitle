import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import '../../models/audio_clip.dart';
import '../../models/subtitle_segment.dart';
import '../../models/video_clip.dart';
import 'clip_ops.dart';
import 'subtitle_ops.dart';

/// CapCut-style multi-track: video clips + captions + audio.
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
    this.thumbnailPath,
    this.height = 196,
  });

  static const minPps = 24.0;
  static const maxPps = 180.0;
  static const pad = 16.0;

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
  final double height;

  @override
  State<CaptionTimeline> createState() => _CaptionTimelineState();
}

class _CaptionTimelineState extends State<CaptionTimeline> {
  final _scroll = ScrollController();
  double _pps = 56;
  bool _followPlayhead = true;
  double _scaleStartPps = 56;

  double get _totalWidth {
    final secs = widget.duration.inMilliseconds / 1000.0;
    return (secs * _pps).clamp(360.0, 250000.0) + CaptionTimeline.pad * 2;
  }

  double _xFor(Duration d) =>
      CaptionTimeline.pad + (d.inMilliseconds / 1000.0) * _pps;

  Duration _timeFor(double x) {
    final secs = ((x - CaptionTimeline.pad) / _pps)
        .clamp(0.0, widget.duration.inMilliseconds / 1000.0);
    return Duration(milliseconds: (secs * 1000).round());
  }

  void _zoomTo(double next, {Offset? focal}) {
    next = next.clamp(CaptionTimeline.minPps, CaptionTimeline.maxPps);
    if ((next - _pps).abs() < 0.4) return;
    final viewport = _scroll.hasClients
        ? _scroll.position.viewportDimension
        : MediaQuery.sizeOf(context).width;
    final focalX = focal?.dx ?? (viewport / 2);
    final contentX = (_scroll.hasClients ? _scroll.offset : 0) + focalX;
    final timeAtFocal = _timeFor(contentX);
    setState(() => _pps = next);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final newX = _xFor(timeAtFocal) - focalX;
      _scroll.jumpTo(newX.clamp(0.0, _scroll.position.maxScrollExtent));
    });
  }

  void _ensurePlayheadVisible() {
    if (!_followPlayhead || !_scroll.hasClients) return;
    final x = _xFor(widget.position);
    final left = _scroll.offset;
    final right = left + _scroll.position.viewportDimension;
    const margin = 56.0;
    if (x < left + margin) {
      _scroll.jumpTo((x - margin).clamp(0.0, _scroll.position.maxScrollExtent));
    } else if (x > right - margin) {
      _scroll.jumpTo(
        (x - _scroll.position.viewportDimension + margin)
            .clamp(0.0, _scroll.position.maxScrollExtent),
      );
    }
  }

  @override
  void didUpdateWidget(covariant CaptionTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.position != widget.position) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _ensurePlayheadVisible());
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

    return Container(
      height: widget.height,
      color: AppColors.timelineTrack,
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                const SizedBox(height: 28),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: const [
                      Text('V',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: AppColors.textMuted)),
                      Text('C',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: AppColors.timelineClip)),
                      Text('A',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF30D158))),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
        children: [
          SizedBox(
            height: 28,
            child: Row(
              children: [
                const SizedBox(width: 6),
                _ZoomIcon(
                  icon: Icons.remove,
                  onTap: () => _zoomTo(_pps * 0.8),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 1.5,
                      activeTrackColor: AppColors.textMuted,
                      inactiveTrackColor: AppColors.border,
                      thumbColor: Colors.white,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 5),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 10),
                    ),
                    child: Slider(
                      min: CaptionTimeline.minPps,
                      max: CaptionTimeline.maxPps,
                      value: _pps.clamp(
                        CaptionTimeline.minPps,
                        CaptionTimeline.maxPps,
                      ),
                      onChanged: (v) {
                        _followPlayhead = false;
                        _zoomTo(v);
                      },
                    ),
                  ),
                ),
                _ZoomIcon(
                  icon: Icons.add,
                  onTap: () => _zoomTo(_pps * 1.25),
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
          Expanded(
            child: GestureDetector(
              onScaleStart: (_) {
                _scaleStartPps = _pps;
                _followPlayhead = false;
              },
              onScaleUpdate: (d) {
                if (d.pointerCount >= 2) {
                  _zoomTo(_scaleStartPps * d.scale, focal: d.localFocalPoint);
                }
              },
              child: NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  if (n is UserScrollNotification) _followPlayhead = false;
                  return false;
                },
                child: SingleChildScrollView(
                  controller: _scroll,
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: SizedBox(
                    width: _totalWidth,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _RulerPainter(
                              pps: _pps,
                              pad: CaptionTimeline.pad,
                              duration: widget.duration,
                            ),
                          ),
                        ),
                        // Video track (filmstrip + clip borders)
                        Positioned(
                          left: CaptionTimeline.pad,
                          right: CaptionTimeline.pad,
                          top: 18,
                          height: 40,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: _Filmstrip(
                              width: _totalWidth - CaptionTimeline.pad * 2,
                              thumbnailPath:
                                  thumbOk ? widget.thumbnailPath : null,
                              duration: widget.duration,
                              pps: _pps,
                            ),
                          ),
                        ),
                        for (final clip in ClipOps.sorted(widget.videoClips))
                          Positioned(
                            left: _xFor(clip.timelineStart),
                            width: (_xFor(clip.timelineEnd) -
                                    _xFor(clip.timelineStart))
                                .clamp(12.0, _totalWidth),
                            top: 18,
                            height: 40,
                            child: GestureDetector(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                widget.onSelectClip?.call(clip);
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: clip.id == widget.activeClipId
                                        ? AppColors.brand
                                        : Colors.white24,
                                    width: clip.id == widget.activeClipId
                                        ? 2
                                        : 1,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        // Caption lane bg
                        Positioned(
                          left: CaptionTimeline.pad,
                          right: CaptionTimeline.pad,
                          top: 64,
                          height: 40,
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.surfaceElevated,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ),
                        // Audio lane
                        Positioned(
                          left: CaptionTimeline.pad,
                          right: CaptionTimeline.pad,
                          top: 110,
                          height: 28,
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.surfaceSoft,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.only(left: 8),
                            child: widget.audioClips.isEmpty
                                ? const Text(
                                    'Audio',
                                    style: TextStyle(
                                      color: AppColors.textMuted,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  )
                                : null,
                          ),
                        ),
                        for (final a in widget.audioClips)
                          Positioned(
                            left: _xFor(a.timelineStart),
                            width: (_xFor(a.timelineEnd) -
                                    _xFor(a.timelineStart))
                                .clamp(16.0, _totalWidth),
                            top: 112,
                            height: 24,
                            child: Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFF30D158),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                a.fileName.isEmpty ? 'Music' : a.fileName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                          ),
                        // Empty seek
                        Positioned.fill(
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onTapUp: (d) =>
                                widget.onSeek(_timeFor(d.localPosition.dx)),
                            onHorizontalDragUpdate: (d) {
                              _followPlayhead = false;
                              widget.onSeek(_timeFor(d.localPosition.dx));
                            },
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
                            top: 66,
                            bottom: 48,
                            pps: _pps,
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
                            left: CaptionTimeline.pad + 12,
                            top: 74,
                            child: const Text(
                              'Captions lane · Auto Captions or Add in Text',
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        // Playhead
                        Positioned(
                          left: _xFor(widget.position) - 1,
                          top: 0,
                          bottom: 0,
                          child: IgnorePointer(
                            child: Column(
                              children: [
                                CustomPaint(
                                  size: const Size(12, 10),
                                  painter: _PlayheadTrianglePainter(),
                                ),
                                Expanded(
                                  child: Container(
                                    width: 2,
                                    color: AppColors.playhead,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
          ),
        ],
      ),
    );
  }
}

class _Filmstrip extends StatelessWidget {
  const _Filmstrip({
    required this.width,
    required this.thumbnailPath,
    required this.duration,
    required this.pps,
  });

  final double width;
  final String? thumbnailPath;
  final Duration duration;
  final double pps;

  @override
  Widget build(BuildContext context) {
    const cell = 56.0;
    final count = (width / cell).ceil().clamp(1, 400);
    return ColoredBox(
      color: AppColors.timelineVideo,
      child: Row(
        children: List.generate(count, (i) {
          return SizedBox(
            width: cell,
            height: 44,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (thumbnailPath != null)
                  Image.file(
                    File(thumbnailPath!),
                    fit: BoxFit.cover,
                    opacity: const AlwaysStoppedAnimation(0.85),
                  )
                else
                  Container(color: AppColors.surfaceSoft),
                Align(
                  alignment: Alignment.bottomLeft,
                  child: Container(
                    margin: const EdgeInsets.all(2),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                    color: Colors.black54,
                    child: Text(
                      '${(i * cell / pps).floor()}s',
                      style: const TextStyle(fontSize: 8, color: Colors.white70),
                    ),
                  ),
                ),
                const Align(
                  alignment: Alignment.centerRight,
                  child: VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: Colors.black38,
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

class _TimelineClip extends StatefulWidget {
  const _TimelineClip({
    super.key,
    required this.segment,
    required this.selected,
    required this.left,
    required this.width,
    required this.top,
    required this.bottom,
    required this.pps,
    required this.mediaDuration,
    required this.onSelect,
    required this.onChanged,
  });

  final SubtitleSegment segment;
  final bool selected;
  final double left;
  final double width;
  final double top;
  final double bottom;
  final double pps;
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
      CaptionTimeline.pad + (_start.inMilliseconds / 1000.0) * widget.pps;
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
      bottom: widget.bottom,
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
            gradient: LinearGradient(
              colors: widget.selected
                  ? [AppColors.timelineClipActive, const Color(0xFFFFB800)]
                  : [AppColors.timelineClip, const Color(0xFF0060DF)],
            ),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: widget.selected ? Colors.white : Colors.white24,
              width: widget.selected ? 1.4 : 0.5,
            ),
          ),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Center(
                  child: Text(
                    widget.segment.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textDirection: TextDirection.rtl,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: widget.selected ? Colors.black : Colors.white,
                    ),
                  ),
                ),
              ),
              _edgeHandle(
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
              _edgeHandle(
                left: false,
                onUpdate: (dx) {
                  final deltaMs = (dx / widget.pps * 1000).round();
                  setState(() {
                    var ne = _end + Duration(milliseconds: deltaMs);
                    if (ne > widget.mediaDuration) ne = widget.mediaDuration;
                    if (ne - _start < SubtitleOps.minDuration) {
                      ne = _start + SubtitleOps.minDuration;
                    }
                    _dragEnd = ne;
                    _dragStart ??= widget.segment.start;
                  });
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _edgeHandle({
    required bool left,
    required void Function(double dx) onUpdate,
  }) {
    return Positioned(
      left: left ? 0 : null,
      right: left ? null : 0,
      top: 0,
      bottom: 0,
      width: 14,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) {
          widget.onSelect();
          _dragStart = widget.segment.start;
          _dragEnd = widget.segment.end;
        },
        onHorizontalDragUpdate: (d) => onUpdate(d.delta.dx),
        onHorizontalDragEnd: (_) => _commit(),
        child: Center(
          child: Container(
            width: 3,
            height: 16,
            decoration: BoxDecoration(
              color: widget.selected ? Colors.black87 : Colors.white70,
              borderRadius: BorderRadius.circular(2),
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
    final paint = Paint()..color = AppColors.playhead;
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

class _RulerPainter extends CustomPainter {
  _RulerPainter({
    required this.pps,
    required this.pad,
    required this.duration,
  });

  final double pps;
  final double pad;
  final Duration duration;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.border
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
      final x = pad + s * pps;
      final major = s % (step == 1 ? 5 : step * 2) == 0;
      canvas.drawLine(Offset(x, major ? 0 : 6), Offset(x, 16), paint);
      if (major) {
        final m = s ~/ 60;
        final sec = s % 60;
        textPainter.text = TextSpan(
          text:
              '${m.toString().padLeft(1, '0')}:${sec.toString().padLeft(2, '0')}',
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 9,
            fontWeight: FontWeight.w600,
          ),
        );
        textPainter.layout();
        textPainter.paint(canvas, Offset(x + 2, 0));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RulerPainter oldDelegate) =>
      oldDelegate.pps != pps || oldDelegate.duration != duration;
}

class _ZoomIcon extends StatelessWidget {
  const _ZoomIcon({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 28,
        height: 28,
        child: Icon(icon, size: 16, color: AppColors.textSecondary),
      ),
    );
  }
}
