import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class EditorTopBar extends StatelessWidget {
  const EditorTopBar({
    super.key,
    required this.title,
    required this.onBack,
    required this.onExport,
    required this.exporting,
    required this.progress,
  });

  final String title;
  final VoidCallback onBack;
  final VoidCallback onExport;
  final bool exporting;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      color: AppColors.background,
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.close, size: 22),
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
          ),
          if (exporting)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Text(
                '${(progress * 100).toStringAsFixed(0)}%',
                style: const TextStyle(
                  color: AppColors.playhead,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: SizedBox(
              height: 32,
              child: ElevatedButton(
                onPressed: onExport,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                child: Text(exporting ? '…' : 'Export'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
