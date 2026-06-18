import 'dart:convert';
import 'dart:html' as html;

Future<String> saveBackupFile(String filename, String content) async {
  final bytes = utf8.encode(content);
  final blob = html.Blob([bytes], 'application/json;charset=utf-8');
  final url = html.Url.createObjectUrlFromBlob(blob);

  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..style.display = 'none';

  html.document.body?.children.add(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);

  return 'Download started: $filename. Check your browser Downloads folder.';
}

Future<String> createLocalAttachmentPath(String filename) async => filename;
