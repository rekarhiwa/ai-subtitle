import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/timestamp_utils.dart';

/// CapCut-style play strip under preview (no scrubber — playhead lives on timeline).
class EditorTransport extends StatelessWidget {
  const EditorTransport({
    super.key,
    required this.position,
    required this.duration,
    required this.playing,
    required this.onPlayPause,
    required this.onSeek,
  });

  final Duration position;
  final Duration duration;
  final bool playing;
  final VoidCallback onPlayPause;
  final ValueChanged<Duration> onSeek;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      color: AppColors.background,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: onPlayPause,
            child: Icon(
              playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            TimestampUtils.toUi(position),
            style: const TextStyle(
              fontSize: 12,
              fontFeatures: [FontFeature.tabularFigures()],
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            ' / ${TimestampUtils.toUi(duration)}',
            style: const TextStyle(
              fontSize: 12,
              fontFeatures: [FontFeature.tabularFigures()],
              color: AppColors.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: '−1s',
            visualDensity: VisualDensity.compact,
            onPressed: () {
              final next = position - const Duration(seconds: 1);
              onSeek(next < Duration.zero ? Duration.zero : next);
            },
            icon: const Icon(Icons.replay_rounded, size: 18),
            color: AppColors.textSecondary,
          ),
        ],
      ),
    );
  }
}
