import 'package:flutter/material.dart';

/// All subtitle appearance comes from this model (preview + ASS export).
class SubtitleStyle {
  const SubtitleStyle({
    this.fontFamily = 'NotoSansArabic',
    this.fontSize = 52,
    this.fontWeight = FontWeight.w700,
    this.textColor = Colors.white,
    this.outlineColor = const Color(0xCC000000),
    this.outlineWidth = 2.5,
    this.shadowColor = const Color(0x99000000),
    this.shadowBlur = 6,
    this.shadowOffset = const Offset(0, 2),
    this.backgroundColor = Colors.transparent,
    this.backgroundOpacity = 0.0,
    this.positionX = 0.5,
    this.positionY = 0.72,
    this.alignment = TextAlign.center,
    this.lineHeight = 1.35,
    this.letterSpacing = 0,
    this.maxWidth = 0.86,
  });

  final String fontFamily;
  final double fontSize;
  final FontWeight fontWeight;
  final Color textColor;
  final Color outlineColor;
  final double outlineWidth;
  final Color shadowColor;
  final double shadowBlur;
  final Offset shadowOffset;
  final Color backgroundColor;
  final double backgroundOpacity;

  /// Normalized horizontal position (0–1). 0.5 = center.
  final double positionX;

  /// Normalized vertical position (0–1). 0 = top, 1 = bottom.
  final double positionY;

  final TextAlign alignment;
  final double lineHeight;
  final double letterSpacing;

  /// Fraction of video width for subtitle max width.
  final double maxWidth;

  SubtitleStyle copyWith({
    String? fontFamily,
    double? fontSize,
    FontWeight? fontWeight,
    Color? textColor,
    Color? outlineColor,
    double? outlineWidth,
    Color? shadowColor,
    double? shadowBlur,
    Offset? shadowOffset,
    Color? backgroundColor,
    double? backgroundOpacity,
    double? positionX,
    double? positionY,
    TextAlign? alignment,
    double? lineHeight,
    double? letterSpacing,
    double? maxWidth,
  }) {
    return SubtitleStyle(
      fontFamily: fontFamily ?? this.fontFamily,
      fontSize: fontSize ?? this.fontSize,
      fontWeight: fontWeight ?? this.fontWeight,
      textColor: textColor ?? this.textColor,
      outlineColor: outlineColor ?? this.outlineColor,
      outlineWidth: outlineWidth ?? this.outlineWidth,
      shadowColor: shadowColor ?? this.shadowColor,
      shadowBlur: shadowBlur ?? this.shadowBlur,
      shadowOffset: shadowOffset ?? this.shadowOffset,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      backgroundOpacity: backgroundOpacity ?? this.backgroundOpacity,
      positionX: positionX ?? this.positionX,
      positionY: positionY ?? this.positionY,
      alignment: alignment ?? this.alignment,
      lineHeight: lineHeight ?? this.lineHeight,
      letterSpacing: letterSpacing ?? this.letterSpacing,
      maxWidth: maxWidth ?? this.maxWidth,
    );
  }

  Map<String, dynamic> toJson() => {
        'fontFamily': fontFamily,
        'fontSize': fontSize,
        'fontWeight': fontWeight.value,
        'textColor': textColor.toARGB32(),
        'outlineColor': outlineColor.toARGB32(),
        'outlineWidth': outlineWidth,
        'shadowColor': shadowColor.toARGB32(),
        'shadowBlur': shadowBlur,
        'shadowOffsetX': shadowOffset.dx,
        'shadowOffsetY': shadowOffset.dy,
        'backgroundColor': backgroundColor.toARGB32(),
        'backgroundOpacity': backgroundOpacity,
        'positionX': positionX,
        'positionY': positionY,
        'alignment': alignment.name,
        'lineHeight': lineHeight,
        'letterSpacing': letterSpacing,
        'maxWidth': maxWidth,
      };
}
