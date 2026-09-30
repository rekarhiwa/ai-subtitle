import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/timestamp_utils.dart';

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
    final maxMs = duration.inMilliseconds.clamp(1, 1 << 62).toDouble();
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(4, 2, 8, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: onPlayPause,
            icon: Icon(
              playing ? Icons.pause_circle_filled : Icons.play_circle_filled,
            ),
            color: AppColors.brand,
            iconSize: 34,
          ),
          Text(
            '${TimestampUtils.toUi(position)} / ${TimestampUtils.toUi(duration)}',
            style: const TextStyle(
              fontSize: 12,
              fontFeatures: [FontFeature.tabularFigures()],
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2.5,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              ),
              child: Slider(
                value: position.inMilliseconds.clamp(0, maxMs.toInt()).toDouble(),
                max: maxMs,
                onChanged: (v) => onSeek(Duration(milliseconds: v.round())),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
