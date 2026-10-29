import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// CapCut top chrome — close / undo / redo / add / white Export pill.
class EditorTopBar extends StatelessWidget {
  const EditorTopBar({
    super.key,
    required this.title,
    required this.onBack,
    required this.onExport,
    required this.exporting,
    required this.progress,
    this.onUndo,
    this.onRedo,
    this.onAddMedia,
    this.canUndo = false,
    this.canRedo = false,
  });

  final String title;
  final VoidCallback onBack;
  final VoidCallback onExport;
  final bool exporting;
  final double progress;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final VoidCallback? onAddMedia;
  final bool canUndo;
  final bool canRedo;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            _iconBtn(Icons.close_rounded, onBack),
            _iconBtn(
              Icons.undo_rounded,
              canUndo ? onUndo : null,
              dim: !canUndo,
            ),
            _iconBtn(
              Icons.redo_rounded,
              canRedo ? onRedo : null,
              dim: !canRedo,
            ),
            _iconBtn(Icons.add_rounded, onAddMedia),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ),
            if (exporting)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(
                  '${(progress * 100).clamp(0, 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                    color: AppColors.playhead,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            GestureDetector(
              onTap: onExport,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 13, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  exporting ? '…' : 'Export',
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback? onTap, {bool dim = false}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 8),
        child: Icon(
          icon,
          size: 20,
          color: dim ? const Color(0xFF3A3A3A) : Colors.white,
        ),
      ),
    );
  }
}
