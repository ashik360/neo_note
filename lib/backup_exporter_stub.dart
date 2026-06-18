Future<String> saveBackupFile(String filename, String content) async {
  throw UnsupportedError('File export is not supported on this platform.');
}

Future<String> createLocalAttachmentPath(String filename) async => filename;
