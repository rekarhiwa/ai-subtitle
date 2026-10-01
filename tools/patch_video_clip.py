from pathlib import Path

p = Path(r'C:\Users\rekar\Desktop\project\subtitle\lib\models\video_clip.dart')
t = p.read_text(encoding='utf-8')

replacements = [
(
"""    this.transitionOut = 'none',
  });""",
"""    this.transitionOut = 'none',
    this.zoom = 1.0,
    this.panX = 0.0,
    this.panY = 0.0,
    this.hue = 0.0,
    this.blendMode = 'normal',
    this.effectId = 'none',
  });""",
),
(
"""  final String transitionOut;

  Duration get rawTrimmed {""",
"""  final String transitionOut;
  final double zoom;
  final double panX;
  final double panY;
  final double hue;
  final String blendMode;
  final String effectId;

  Duration get rawTrimmed {""",
),
]

for old, new in replacements:
    if old not in t:
        raise SystemExit(f'missing block:\n{old[:80]}')
    t = t.replace(old, new, 1)

# create factory params
old = """    String transitionOut = 'none',
  }) {"""
new = """    String transitionOut = 'none',
    double zoom = 1.0,
    double panX = 0.0,
    double panY = 0.0,
    double hue = 0.0,
    String blendMode = 'normal',
    String effectId = 'none',
  }) {"""
if old not in t:
    raise SystemExit('create params missing')
t = t.replace(old, new, 1)

old = """      transitionOut: transitionOut,
    );
  }

  factory VideoClip.fromJson"""
new = """      transitionOut: transitionOut,
      zoom: zoom,
      panX: panX,
      panY: panY,
      hue: hue,
      blendMode: blendMode,
      effectId: effectId,
    );
  }

  factory VideoClip.fromJson"""
if old not in t:
    raise SystemExit('create body missing')
t = t.replace(old, new, 1)

old = """      transitionOut: json['transitionOut'] as String? ?? 'none',
    );
  }

  Map<String, dynamic> toJson"""
new = """      transitionOut: json['transitionOut'] as String? ?? 'none',
      zoom: (json['zoom'] as num?)?.toDouble() ?? 1.0,
      panX: (json['panX'] as num?)?.toDouble() ?? 0.0,
      panY: (json['panY'] as num?)?.toDouble() ?? 0.0,
      hue: (json['hue'] as num?)?.toDouble() ?? 0.0,
      blendMode: json['blendMode'] as String? ?? 'normal',
      effectId: json['effectId'] as String? ?? 'none',
    );
  }

  Map<String, dynamic> toJson"""
if old not in t:
    raise SystemExit('fromJson missing')
t = t.replace(old, new, 1)

old = """        'transitionOut': transitionOut,
      };"""
new = """        'transitionOut': transitionOut,
        'zoom': zoom,
        'panX': panX,
        'panY': panY,
        'hue': hue,
        'blendMode': blendMode,
        'effectId': effectId,
      };"""
if old not in t:
    raise SystemExit('toJson missing')
t = t.replace(old, new, 1)

old = """    String? transitionOut,
  }) {"""
new = """    String? transitionOut,
    double? zoom,
    double? panX,
    double? panY,
    double? hue,
    String? blendMode,
    String? effectId,
  }) {"""
if old not in t:
    raise SystemExit('copyWith params missing')
t = t.replace(old, new, 1)

old = """      transitionOut: transitionOut ?? this.transitionOut,
    );
  }

  /// Copy effects"""
new = """      transitionOut: transitionOut ?? this.transitionOut,
      zoom: zoom ?? this.zoom,
      panX: panX ?? this.panX,
      panY: panY ?? this.panY,
      hue: hue ?? this.hue,
      blendMode: blendMode ?? this.blendMode,
      effectId: effectId ?? this.effectId,
    );
  }

  /// Copy effects"""
if old not in t:
    raise SystemExit('copyWith body missing')
t = t.replace(old, new, 1)

old = """      transitionOut: transitionOut,
    );
  }
}
"""
new = """      transitionOut: transitionOut,
      zoom: zoom,
      panX: panX,
      panY: panY,
      hue: hue,
      blendMode: blendMode,
      effectId: effectId,
    );
  }
}
"""
# duplicateAt may already pass transitionOut at end
if 'zoom: zoom,' not in t.split('duplicateAt')[-1]:
    # patch duplicateAt create call
    marker = '      transitionOut: transitionOut,\n    );\n  }\n}\n'
    if marker not in t:
        raise SystemExit('duplicateAt end missing')
    t = t.replace(marker, """      transitionOut: transitionOut,
      zoom: zoom,
      panX: panX,
      panY: panY,
      hue: hue,
      blendMode: blendMode,
      effectId: effectId,
    );
  }
}
""", 1)

p.write_text(t, encoding='utf-8')
print('video_clip updated')
