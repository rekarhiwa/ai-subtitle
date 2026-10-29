import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';

enum CanvasManipTarget { caption, sticker }

/// CapCut-like touch manip: drag to move, pinch to scale.
class CanvasManipulator extends StatefulWidget {
  const CanvasManipulator({
    super.key,
    required this.canvasSize,
    required this.nx,
    required this.ny,
    required this.scale,
    required this.minScale,
    required this.maxScale,
    required this.selected,
    required this.onSelected,
    required this.onChanged,
    required this.onCommit,
    required this.child,
    this.showHandles = true,
    this.maxWidthFraction = 0.9,
  });

  final Size canvasSize;
  final double nx;
  final double ny;
  final double scale;
  final double minScale;
  final double maxScale;
  final bool selected;
  final VoidCallback onSelected;
  final void Function(double nx, double ny, double scale) onChanged;
  final void Function(double nx, double ny, double scale) onCommit;
  final Widget child;
  final bool showHandles;
  final double maxWidthFraction;

  @override
  State<CanvasManipulator> createState() => _CanvasManipulatorState();
}

class _CanvasManipulatorState extends State<CanvasManipulator> {
  late double _nx;
  late double _ny;
  late double _scale;
  double _baseScale = 1;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _nx = widget.nx;
    _ny = widget.ny;
    _scale = widget.scale;
  }

  @override
  void didUpdateWidget(covariant CanvasManipulator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dragging) {
      _nx = widget.nx;
      _ny = widget.ny;
      _scale = widget.scale;
    }
  }

  void _emitLive() {
    widget.onChanged(
      _nx.clamp(0.05, 0.95),
      _ny.clamp(0.05, 0.95),
      _scale.clamp(widget.minScale, widget.maxScale),
    );
  }

  void _emitCommit() {
    widget.onCommit(
      _nx.clamp(0.05, 0.95),
      _ny.clamp(0.05, 0.95),
      _scale.clamp(widget.minScale, widget.maxScale),
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxW = widget.canvasSize.width * widget.maxWidthFraction;
    return Positioned.fill(
      child: Align(
        alignment: Alignment((_nx * 2) - 1, (_ny * 2) - 1),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            HapticFeedback.selectionClick();
            widget.onSelected();
          },
          onScaleStart: (_) {
            widget.onSelected();
            _dragging = true;
            _baseScale = _scale;
            HapticFeedback.lightImpact();
          },
          onScaleUpdate: (d) {
            final w = widget.canvasSize.width.clamp(1, 10000);
            final h = widget.canvasSize.height.clamp(1, 10000);
            setState(() {
              _nx = (_nx + d.focalPointDelta.dx / w).clamp(0.05, 0.95);
              _ny = (_ny + d.focalPointDelta.dy / h).clamp(0.05, 0.95);
              if (d.pointerCount >= 2) {
                _scale = (_baseScale * d.scale)
                    .clamp(widget.minScale, widget.maxScale);
              }
            });
            _emitLive();
          },
          onScaleEnd: (_) {
            _dragging = false;
            _emitCommit();
            HapticFeedback.selectionClick();
          },
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxW),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: widget.child,
                ),
                if (widget.selected && widget.showHandles)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: AppColors.playhead,
                            width: 1.5,
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ),
                if (widget.selected && widget.showHandles) ...[
                  _corner(-6, -6),
                  _corner(null, -6, right: -6),
                  _corner(-6, null, bottom: -6),
                  _corner(null, null, right: -6, bottom: -6),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _corner(double? left, double? top, {double? right, double? bottom}) {
    return Positioned(
      left: left,
      top: top,
      right: right,
      bottom: bottom,
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: AppColors.playhead,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(color: Colors.black, width: 1),
        ),
      ),
    );
  }
}
