import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/config/app_config.dart';
import '../storage/secure_storage_service.dart';

class TempFileService {
  TempFileService(this._storage);

  final SecureStorageService _storage;
  final Set<String> _tracked = {};

  Future<Directory> root() async {
    final override = await _storage.getTempDirectoryOverride();
    if (override != null && override.isNotEmpty) {
      final dir = Directory(override);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir;
    }

    final base = await getTemporaryDirectory();
    final dir = Directory(p.join(base.path, AppConfig.tempFolderName));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<String> createPath(String fileName) async {
    final dir = await root();
    final path = p.join(dir.path, fileName);
    _tracked.add(path);
    return path;
  }

  Future<File> createFile(String fileName) async {
    final path = await createPath(fileName);
    return File(path);
  }

  void track(String path) => _tracked.add(path);

  Future<void> delete(String path) async {
    try {
      final entity = FileSystemEntity.typeSync(path);
      if (entity == FileSystemEntityType.file) {
        await File(path).delete();
      } else if (entity == FileSystemEntityType.directory) {
        await Directory(path).delete(recursive: true);
      }
    } catch (_) {
      // Best-effort cleanup.
    } finally {
      _tracked.remove(path);
    }
  }

  Future<void> clearTracked() async {
    for (final path in _tracked.toList()) {
      await delete(path);
    }
  }

  Future<int> clearAllTempFiles() async {
    final dir = await root();
    var deleted = 0;
    if (!await dir.exists()) return 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      try {
        if (entity is File) {
          await entity.delete();
          deleted++;
        }
      } catch (_) {}
    }
    _tracked.clear();
    return deleted;
  }
}
