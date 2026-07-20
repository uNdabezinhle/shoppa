import 'dart:io';
import 'dart:typed_data';

Future<String> saveListExport({
  required Uint8List bytes,
  required String filename,
  required String contentType,
}) async {
  final safe = filename.replaceAll(RegExp(r'[^\w.\- ]+'), '_');
  final file = File('${Directory.systemTemp.path}${Platform.pathSeparator}$safe');
  await file.writeAsBytes(bytes, flush: true);
  return 'Saved to ${file.path}';
}
