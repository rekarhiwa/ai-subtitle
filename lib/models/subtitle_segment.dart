import 'package:uuid/uuid.dart';

import '../core/utils/timestamp_utils.dart';

class SubtitleSegment {
  SubtitleSegment({
    required this.id,
    required this.start,
    required this.end,
    required this.text,
  });

  final String id;
  Duration start;
  Duration end;
  String text;

  factory SubtitleSegment.create({
    required Duration start,
    required Duration end,
    required String text,
  }) {
    return SubtitleSegment(
      id: const Uuid().v4(),
      start: start,
      end: end,
      text: text.trim(),
    );
  }

  factory SubtitleSegment.fromJson(Map<String, dynamic> json) {
    final startMs = _readInt(json['startMs'] ?? json['start_ms'] ?? json['start']);
    final endMs = _readInt(json['endMs'] ?? json['end_ms'] ?? json['end']);
    final text = (json['text'] ?? '').toString().trim();
    if (startMs < 0) {
      throw FormatException('startMs must be >= 0, got $startMs');
    }
    if (endMs <= startMs) {
      throw FormatException('endMs must be > startMs ($startMs < $endMs)');
    }
    if (text.isEmpty) {
      throw const FormatException('text must not be empty');
    }
    return SubtitleSegment(
      id: (json['id'] ?? const Uuid().v4()).toString(),
      start: TimestampUtils.fromMilliseconds(startMs),
      end: TimestampUtils.fromMilliseconds(endMs),
      text: text,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'startMs': start.inMilliseconds,
        'endMs': end.inMilliseconds,
        'text': text,
      };

  SubtitleSegment copyWith({
    String? id,
    Duration? start,
    Duration? end,
    String? text,
  }) {
    return SubtitleSegment(
      id: id ?? this.id,
      start: start ?? this.start,
      end: end ?? this.end,
      text: text ?? this.text,
    );
  }

  bool contains(Duration position) =>
      position >= start && position < end;

  Duration get duration => end - start;

  static int _readInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.round();
    if (value is String) {
      final asInt = int.tryParse(value);
      if (asInt != null) return asInt;
      final asDouble = double.tryParse(value);
      if (asDouble != null) return asDouble.round();
    }
    throw FormatException('Expected numeric timestamp, got $value');
  }
}
