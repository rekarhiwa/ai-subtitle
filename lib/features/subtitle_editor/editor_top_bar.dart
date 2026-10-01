import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// CapCut-accurate top chrome: close · undo/redo · Export pill.
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
  final bool canUndo;
  final bool canRedo;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          children: [
            IconButton(
              onPressed: onBack,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close_rounded, size: 24),
            ),
            IconButton(
              tooltip: 'Undo',
              onPressed: canUndo ? onUndo : null,
              visualDensity: VisualDensity.compact,
              icon: Icon(
                Icons.undo_rounded,
                size: 20,
                color: canUndo ? AppColors.textPrimary : AppColors.textMuted,
              ),
            ),
            IconButton(
              tooltip: 'Redo',
              onPressed: canRedo ? onRedo : null,
              visualDensity: VisualDensity.compact,
              icon: Icon(
                Icons.redo_rounded,
                size: 20,
                color: canRedo ? AppColors.textPrimary : AppColors.textMuted,
              ),
            ),
            const Spacer(),
            if (exporting)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  '${(progress * 100).clamp(0, 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                    color: AppColors.playhead,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),
            Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                onTap: onExport,
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 8,
                  ),
                  child: Text(
                    exporting ? '…' : 'Export',
                    style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}
