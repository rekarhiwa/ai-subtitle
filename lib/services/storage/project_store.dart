import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../models/montage_project.dart';
import '../../models/video_clip.dart';
import '../../models/video_metadata.dart';

/// Local JSON project store + recent list.
class ProjectStore {
  static const _recentKey = 'montage_recent_ids';
  static const _maxRecent = 20;

  Future<Directory> _projectsDir() async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(root.path, 'montage_projects'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<String> _pathFor(String id) async {
    final dir = await _projectsDir();
    return p.join(dir.path, '$id.json');
  }

  Future<MontageProject> createFromVideo(VideoMetadata video) async {
    final now = DateTime.now();
    final clip = VideoClip.create(
      sourcePath: video.path,
      sourceDuration: video.duration,
      timelineStart: Duration.zero,
      thumbnailPath: video.thumbnailPath,
      fileName: video.fileName,
    );
    final project = MontageProject(
      id: const Uuid().v4(),
      name: p.basenameWithoutExtension(video.fileName),
      createdAt: now,
      updatedAt: now,
      primaryVideo: video,
      videoClips: [clip],
    );
    await save(project);
    return project;
  }

  Future<void> save(MontageProject project) async {
    final path = await _pathFor(project.id);
    final stamped = project.copyWith(updatedAt: DateTime.now());
    await File(path).writeAsString(
      const JsonEncoder.withIndent('  ').convert(stamped.toJson()),
      flush: true,
    );
    await _touchRecent(stamped.id);
  }

  Future<MontageProject?> load(String id) async {
    final path = await _pathFor(id);
    final file = File(path);
    if (!await file.exists()) return null;
    final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    return MontageProject.fromJson(json);
  }

  Future<void> delete(String id) async {
    final path = await _pathFor(id);
    final file = File(path);
    if (await file.exists()) await file.delete();
    final prefs = await SharedPreferences.getInstance();
    final recent = prefs.getStringList(_recentKey) ?? [];
    recent.remove(id);
    await prefs.setStringList(_recentKey, recent);
  }

  Future<void> _touchRecent(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final recent = prefs.getStringList(_recentKey) ?? [];
    recent.remove(id);
    recent.insert(0, id);
    if (recent.length > _maxRecent) {
      recent.removeRange(_maxRecent, recent.length);
    }
    await prefs.setStringList(_recentKey, recent);
  }

  Future<List<MontageProject>> listRecent({int limit = 12}) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_recentKey) ?? [];
    final out = <MontageProject>[];
    for (final id in ids) {
      if (out.length >= limit) break;
      final p = await load(id);
      if (p != null) out.add(p);
    }
    return out;
  }
}
