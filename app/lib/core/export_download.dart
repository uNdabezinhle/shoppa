/// Platform-specific export download/share helpers.
import 'dart:typed_data';

import 'export_download_stub.dart'
    if (dart.library.html) 'export_download_web.dart'
    if (dart.library.io) 'export_download_io.dart' as impl;

/// Saves or triggers a browser download for exported list bytes.
/// Returns a short user-facing status message.
Future<String> saveListExport({
  required Uint8List bytes,
  required String filename,
  required String contentType,
}) {
  return impl.saveListExport(
    bytes: bytes,
    filename: filename,
    contentType: contentType,
  );
}
