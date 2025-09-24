// lib/services/os_open.dart
import 'dart:io' show Platform, Process;
import 'package:path/path.dart' as p;

class OsOpen {
  static Future<void> revealInFileManager(String path) async {
    try {
      if (Platform.isWindows) {
        final winPath = path.replaceAll('/', '\\');
        await Process.run('explorer', ['/select,', winPath]);
      } else if (Platform.isMacOS) {
        await Process.run('open', ['-R', path]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [p.dirname(path)]);
      }
    } catch (_) {}
  }

  static Future<void> openFolder(String folderPath) async {
    try {
      if (Platform.isWindows) {
        final winPath = folderPath.replaceAll('/', '\\');
        await Process.run('explorer', [winPath]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [folderPath]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [folderPath]);
      }
    } catch (_) {}
  }
}
