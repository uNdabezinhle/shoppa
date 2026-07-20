import 'dart:typed_data';

Future<String> saveListExport({
  required Uint8List bytes,
  required String filename,
  required String contentType,
}) async {
  return 'Export ready (${bytes.length} bytes) — open on web or mobile to save.';
}
