from pathlib import Path

p = Path(r'C:\Users\rekar\Desktop\project\subtitle\lib\models\video_clip.dart')
t = p.read_text(encoding='utf-8')

# Add fields after effectId in constructor default list
old = """    this.effectId = 'none',
  });"""
new = """    this.effectId = 'none',
    this.isOverlay = false,
    this.overlayX = 0.7,
    this.overlayY = 0.2,
    this.overlayScale = 0.35,
    this.maskType = 'none',
    this.chromaKey = false,
    this.chromaSimilarity = 0.3,
    this.stabilize = false,
    this.cameraFx = 'none',
    this.beauty = 0.0,
  });"""
if old not in t:
    raise SystemExit('ctor missing')
t = t.replace(old, new, 1)

old = """  final String effectId;

  Duration get rawTrimmed {"""
new = """  final String effectId;
  final bool isOverlay;
  final double overlayX;
  final double overlayY;
  final double overlayScale;
  final String maskType;
  final bool chromaKey;
  final double chromaSimilarity;
  final bool stabilize;
  final String cameraFx;
  final double beauty;

  Duration get rawTrimmed {"""
if old not in t:
    raise SystemExit('fields missing')
t = t.replace(old, new, 1)

old = """    String effectId = 'none',
  }) {"""
new = """    String effectId = 'none',
    bool isOverlay = false,
    double overlayX = 0.7,
    double overlayY = 0.2,
    double overlayScale = 0.35,
    String maskType = 'none',
    bool chromaKey = false,
    double chromaSimilarity = 0.3,
    bool stabilize = false,
    String cameraFx = 'none',
    double beauty = 0.0,
  }) {"""
if old not in t:
    raise SystemExit('create params')
t = t.replace(old, new, 1)

old = """      effectId: effectId,
    );
  }

  factory VideoClip.fromJson"""
new = """      effectId: effectId,
      isOverlay: isOverlay,
      overlayX: overlayX,
      overlayY: overlayY,
      overlayScale: overlayScale,
      maskType: maskType,
      chromaKey: chromaKey,
      chromaSimilarity: chromaSimilarity,
      stabilize: stabilize,
      cameraFx: cameraFx,
      beauty: beauty,
    );
  }

  factory VideoClip.fromJson"""
if old not in t:
    raise SystemExit('create body')
t = t.replace(old, new, 1)

old = """      effectId: json['effectId'] as String? ?? 'none',
    );
  }

  Map<String, dynamic> toJson"""
new = """      effectId: json['effectId'] as String? ?? 'none',
      isOverlay: json['isOverlay'] as bool? ?? false,
      overlayX: (json['overlayX'] as num?)?.toDouble() ?? 0.7,
      overlayY: (json['overlayY'] as num?)?.toDouble() ?? 0.2,
      overlayScale: (json['overlayScale'] as num?)?.toDouble() ?? 0.35,
      maskType: json['maskType'] as String? ?? 'none',
      chromaKey: json['chromaKey'] as bool? ?? false,
      chromaSimilarity: (json['chromaSimilarity'] as num?)?.toDouble() ?? 0.3,
      stabilize: json['stabilize'] as bool? ?? false,
      cameraFx: json['cameraFx'] as String? ?? 'none',
      beauty: (json['beauty'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson"""
if old not in t:
    raise SystemExit('fromJson')
t = t.replace(old, new, 1)

old = """        'effectId': effectId,
      };"""
new = """        'effectId': effectId,
        'isOverlay': isOverlay,
        'overlayX': overlayX,
        'overlayY': overlayY,
        'overlayScale': overlayScale,
        'maskType': maskType,
        'chromaKey': chromaKey,
        'chromaSimilarity': chromaSimilarity,
        'stabilize': stabilize,
        'cameraFx': cameraFx,
        'beauty': beauty,
      };"""
if old not in t:
    raise SystemExit('toJson')
t = t.replace(old, new, 1)

old = """    String? effectId,
  }) {"""
new = """    String? effectId,
    bool? isOverlay,
    double? overlayX,
    double? overlayY,
    double? overlayScale,
    String? maskType,
    bool? chromaKey,
    double? chromaSimilarity,
    bool? stabilize,
    String? cameraFx,
    double? beauty,
  }) {"""
if old not in t:
    raise SystemExit('copyWith params')
t = t.replace(old, new, 1)

old = """      effectId: effectId ?? this.effectId,
    );
  }

  /// Copy effects"""
new = """      effectId: effectId ?? this.effectId,
      isOverlay: isOverlay ?? this.isOverlay,
      overlayX: overlayX ?? this.overlayX,
      overlayY: overlayY ?? this.overlayY,
      overlayScale: overlayScale ?? this.overlayScale,
      maskType: maskType ?? this.maskType,
      chromaKey: chromaKey ?? this.chromaKey,
      chromaSimilarity: chromaSimilarity ?? this.chromaSimilarity,
      stabilize: stabilize ?? this.stabilize,
      cameraFx: cameraFx ?? this.cameraFx,
      beauty: beauty ?? this.beauty,
    );
  }

  /// Copy effects"""
if old not in t:
    raise SystemExit('copyWith body')
t = t.replace(old, new, 1)

# duplicateAt
old = """      effectId: effectId,
    );
  }
}
"""
new = """      effectId: effectId,
      isOverlay: isOverlay,
      overlayX: overlayX,
      overlayY: overlayY,
      overlayScale: overlayScale,
      maskType: maskType,
      chromaKey: chromaKey,
      chromaSimilarity: chromaSimilarity,
      stabilize: stabilize,
      cameraFx: cameraFx,
      beauty: beauty,
    );
  }
}
"""
if old not in t:
    raise SystemExit('duplicateAt')
t = t.replace(old, new, 1)

p.write_text(t, encoding='utf-8')
print('video_clip batch2 ok')
