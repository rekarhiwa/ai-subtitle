import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/utils/timestamp_utils.dart';

/// CapCut transport strip: time left · play center · actions right.
class EditorTransport extends StatelessWidget {
  const EditorTransport({
    super.key,
    required this.position,
    required this.duration,
    required this.playing,
    required this.onPlayPause,
    required this.onSeek,
    this.canUndo = false,
    this.canRedo = false,
    this.onUndo,
    this.onRedo,
    this.onKeyframe,
    this.onFullscreen,
    this.fullscreen = false,
  });

  final Duration position;
  final Duration duration;
  final bool playing;
  final VoidCallback onPlayPause;
  final ValueChanged<Duration> onSeek;
  final bool canUndo;
  final bool canRedo;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final VoidCallback? onKeyframe;
  final VoidCallback? onFullscreen;
  final bool fullscreen;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      color: const Color(0xFF000000),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          // Left: timecode
          SizedBox(
            width: 110,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: TimestampUtils.toUi(position),
                    style: const TextStyle(
                      fontSize: 12,
                      fontFeatures: [FontFeature.tabularFigures()],
                      color: Color(0xFFB0B0B0),
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.2,
                    ),
                  ),
                  TextSpan(
                    text: ' / ${TimestampUtils.toUi(duration)}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontFeatures: [FontFeature.tabularFigures()],
                      color: Color(0xFF5A5A5A),
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Center: play
          Expanded(
            child: Center(
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  onPlayPause();
                },
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Icon(
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
              ),
            ),
          ),
          // Right: keyframe · undo · redo · fullscreen
          SizedBox(
            width: 132,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _TransportIcon(
                  icon: Icons.diamond_outlined,
                  onTap: onKeyframe,
                  enabled: onKeyframe != null,
                ),
                _TransportIcon(
                  icon: Icons.undo_rounded,
                  onTap: canUndo ? onUndo : null,
                  enabled: canUndo,
                ),
                _TransportIcon(
                  icon: Icons.redo_rounded,
                  onTap: canRedo ? onRedo : null,
                  enabled: canRedo,
                ),
                _TransportIcon(
                  icon: fullscreen
                      ? Icons.fullscreen_exit_rounded
                      : Icons.fullscreen_rounded,
                  onTap: onFullscreen,
                  enabled: onFullscreen != null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TransportIcon extends StatelessWidget {
  const _TransportIcon({
    required this.icon,
    this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: !enabled || onTap == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              onTap!();
            },
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 8),
        child: Icon(
          icon,
          size: 20,
          color: enabled ? Colors.white : const Color(0xFF3A3A3A),
        ),
      ),
    );
  }
}
