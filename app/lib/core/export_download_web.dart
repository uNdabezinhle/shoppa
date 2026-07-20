import 'dart:html' as html;
import 'dart:typed_data';

Future<String> saveListExport({
  required Uint8List bytes,
  required String filename,
  required String contentType,
}) async {
  final blob = html.Blob([bytes], contentType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
  return 'Downloaded $filename';
}
