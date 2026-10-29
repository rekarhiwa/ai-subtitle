import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';

/// CapCut tool icon — compact glyph + 9px label.
class CapCutToolIcon extends StatelessWidget {
  const CapCutToolIcon({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.enabled = true,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool selected;
  final bool enabled;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = !enabled
        ? const Color(0xFF454545)
        : danger
            ? AppColors.danger
            : selected
                ? Colors.white
                : const Color(0xFF9A9A9A);
    return InkWell(
      onTap: !enabled
          ? null
          : () {
              HapticFeedback.selectionClick();
              onTap?.call();
            },
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 52,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                letterSpacing: -0.2,
                height: 1.1,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// CapCut bottom drawer chrome — handle, title, dismiss.
class CapCutSheetChrome extends StatelessWidget {
  const CapCutSheetChrome({
    super.key,
    required this.title,
    required this.child,
    this.onClose,
  });

  final String title;
  final Widget child;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF0E0E0E),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF3A3A3A),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          SizedBox(
            height: 40,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  if (onClose != null)
                    GestureDetector(
                      onTap: onClose,
                      behavior: HitTestBehavior.opaque,
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 22,
                          color: Color(0xFF8E8E8E),
                        ),
                      ),
                    )
                  else
                    const SizedBox(width: 38),
                  Expanded(
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  const SizedBox(width: 38),
                ],
              ),
            ),
          ),
          const Divider(height: 1, color: Color(0xFF1C1C1C)),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// White / outline CapCut pill.
class CapCutPillButton extends StatelessWidget {
  const CapCutPillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.filled = true,
    this.busy = false,
    this.expanded = false,
    this.height = 36,
    this.danger = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool filled;
  final bool busy;
  final bool expanded;
  final double height;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    final bg = !filled
        ? Colors.transparent
        : danger
            ? AppColors.danger
            : Colors.white;
    final fg = !filled
        ? (danger ? AppColors.danger : Colors.white)
        : danger
            ? Colors.white
            : Colors.black;

    final child = busy
        ? SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: filled ? Colors.black : Colors.white,
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: fg),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: fg.withValues(alpha: enabled ? 1 : 0.4),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ],
          );

    return GestureDetector(
      onTap: !enabled
          ? null
          : () {
              HapticFeedback.lightImpact();
              onPressed!();
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        height: height,
        width: expanded ? double.infinity : null,
        padding: EdgeInsets.symmetric(horizontal: expanded ? 16 : 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg.withValues(alpha: enabled || !filled ? 1 : 0.35),
          borderRadius: BorderRadius.circular(height / 2),
          border: filled
              ? null
              : Border.all(
                  color: danger ? AppColors.danger : const Color(0xFF333333),
                ),
        ),
        child: child,
      ),
    );
  }
}

/// Compact section title.
class CapCutSectionTitle extends StatelessWidget {
  const CapCutSectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(
            text,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF8E8E8E),
              letterSpacing: 0.2,
            ),
          ),
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}
