import 'dart:io';
import 'package:path_provider/path_provider.dart';

Future<String> saveBackupFile(String filename, String content) async {
  final targetDir = await _resolveWritableExportDirectory();
  final file = await _createUniqueBackupFile(targetDir, filename);
  await file.writeAsString(content, flush: true);
  return 'Backup saved to local storage: ${file.path}';
}

Future<String> createLocalAttachmentPath(String filename) async {
  final baseDir = await _resolveWritableAttachmentDirectory();
  if (!await baseDir.exists()) {
    await baseDir.create(recursive: true);
  }
  return '${baseDir.path}${Platform.pathSeparator}$filename';
}

Future<Directory> _resolveWritableAttachmentDirectory() async {
  try {
    final docs = await getApplicationDocumentsDirectory();
    return Directory('${docs.path}${Platform.pathSeparator}neonote_attachments');
  } catch (_) {
    return Directory('${Directory.systemTemp.path}${Platform.pathSeparator}neonote_attachments');
  }
}

Future<Directory> _resolveWritableExportDirectory() async {
  final candidates = <Directory>[];

  Future<void> addPathProviderFolders() async {
    try {
      final downloadsDir = await getDownloadsDirectory();
      if (downloadsDir != null) candidates.add(downloadsDir);
    } catch (_) {}

    try {
      candidates.add(await getApplicationDocumentsDirectory());
    } catch (_) {}
  }

  await addPathProviderFolders();

  if (Platform.isAndroid) {
    candidates.addAll([
      Directory('/storage/emulated/0/Download'),
      Directory('/sdcard/Download'),
    ]);
  }

  final home = Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      Platform.environment['HOMEPATH'];
  if (home != null && home.trim().isNotEmpty) {
    candidates.add(Directory('$home${Platform.pathSeparator}Downloads'));
  }

  candidates.add(Directory.systemTemp);

  final checked = <String>{};
  for (final dir in candidates) {
    if (!checked.add(dir.path)) continue;

    try {
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final probe = File('${dir.path}${Platform.pathSeparator}.neonote_export_probe');
      await probe.writeAsString('ok', flush: true);
      if (await probe.exists()) await probe.delete();
      return dir;
    } catch (_) {}
  }

  throw Exception('No writable export folder found on this device.');
}

Future<File> _createUniqueBackupFile(Directory targetDir, String filename) async {
  var candidate = File('${targetDir.path}${Platform.pathSeparator}$filename');
  if (await candidate.exists()) {
    final baseName = filename.replaceFirst('.json', '');
    var counter = 1;
    while (await candidate.exists()) {
      candidate = File('${targetDir.path}${Platform.pathSeparator}${baseName}_$counter.json');
      counter++;
    }
  }
  return candidate;
}
