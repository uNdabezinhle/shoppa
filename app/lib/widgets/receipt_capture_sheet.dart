import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../core/list_shop_helpers.dart';
import '../core/lists_repository.dart';
import '../core/receipt_capture.dart';
import '../theme/shoppa_theme.dart';

/// Capture a trip total from manual entry, pasted text, or a receipt photo.
///
/// Photos go through [ReceiptOcrService.parseImageBytes]. The default
/// heuristic service attaches the photo and asks for a manual total until
/// a real OCR backend is plugged in.
Future<ReceiptCapture?> showReceiptCaptureSheet(
  BuildContext context, {
  required List<ShoppaListItem> items,
  ReceiptOcrService? ocr,
  ImagePicker? imagePicker,
  String? initialStoreName,
  List<String> suggestedStores = const [],
}) {
  return showModalBottomSheet<ReceiptCapture>(
    context: context,
    isScrollControlled: true,
    backgroundColor: ShoppaColors.panel,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _ReceiptCaptureSheet(
      items: items,
      ocr: ocr ?? HeuristicReceiptOcrService(),
      imagePicker: imagePicker ?? ImagePicker(),
      initialStoreName: initialStoreName ?? '',
      suggestedStores: suggestedStores,
    ),
  );
}

class _ReceiptCaptureSheet extends StatefulWidget {
  const _ReceiptCaptureSheet({
    required this.items,
    required this.ocr,
    required this.imagePicker,
    required this.initialStoreName,
    required this.suggestedStores,
  });

  final List<ShoppaListItem> items;
  final ReceiptOcrService ocr;
  final ImagePicker imagePicker;
  final String initialStoreName;
  final List<String> suggestedStores;

  @override
  State<_ReceiptCaptureSheet> createState() => _ReceiptCaptureSheetState();
}

class _ReceiptCaptureSheetState extends State<_ReceiptCaptureSheet> {
  late final TextEditingController _totalController;
  late final TextEditingController _storeController;
  late final TextEditingController _notesController;
  late final TextEditingController _pasteController;
  bool _parsing = false;
  String? _parseHint;
  ReceiptSource _source = ReceiptSource.manual;
  bool _hasPhoto = false;
  int _photoByteLength = 0;
  List<String> _lineHints = const [];
  List<String> _unmatchedHints = const [];
  final Set<String> _selectedAdds = {};

  @override
  void initState() {
    super.initState();
    final spend = tripSpend(widget.items);
    _totalController = TextEditingController(
      text: spend.hasSpend ? (spend.spentCents / 100).toStringAsFixed(2) : '',
    );
    _storeController = TextEditingController(text: widget.initialStoreName);
    _notesController = TextEditingController();
    _pasteController = TextEditingController();
  }

  @override
  void dispose() {
    _totalController.dispose();
    _storeController.dispose();
    _notesController.dispose();
    _pasteController.dispose();
    super.dispose();
  }

  int? _parseTotalField() {
    final raw = _totalController.text.trim().replaceAll(',', '.');
    if (raw.isEmpty) return null;
    final rands = double.tryParse(raw.replaceAll(RegExp(r'[^\d.]'), ''));
    if (rands == null || rands <= 0) return null;
    return (rands * 100).round();
  }

  void _applyHints(List<String> hints) {
    final unmatched = unmatchedReceiptLineHints(
      lineHints: hints,
      items: widget.items,
    );
    _lineHints = hints;
    _unmatchedHints = unmatched;
    _selectedAdds
      ..clear()
      ..addAll(unmatched.map(normalizeReceiptItemName));
  }

  Future<void> _parsePasted() async {
    final text = _pasteController.text.trim();
    if (text.isEmpty) {
      setState(() => _parseHint = 'Paste receipt text first');
      return;
    }
    setState(() {
      _parsing = true;
      _parseHint = null;
    });
    try {
      final result = await widget.ocr.parseText(text);
      if (!mounted) return;
      setState(() {
        _parsing = false;
        _source = ReceiptSource.pastedText;
        _applyParseResult(result, keepPhoto: _hasPhoto);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _parsing = false;
        _parseHint = 'Could not parse: $e';
      });
    }
  }

  void _applyParseResult(ReceiptCapture result, {required bool keepPhoto}) {
    if (result.totalCents != null) {
      _totalController.text =
          (result.totalCents! / 100).toStringAsFixed(2);
    }
    if (result.storeName.isNotEmpty && _storeController.text.isEmpty) {
      _storeController.text = result.storeName;
    }
    if (result.rawText.isNotEmpty && _pasteController.text.trim().isEmpty) {
      _pasteController.text = result.rawText;
    }
    if (result.notes.isNotEmpty && _notesController.text.trim().isEmpty) {
      _notesController.text = result.notes;
    }
    if (result.hasPhoto || keepPhoto) {
      _hasPhoto = true;
      if (result.photoByteLength > 0) {
        _photoByteLength = result.photoByteLength;
      }
    }
    _applyHints(result.lineHints);
    final n = result.totalCents != null
        ? 'Found total ${result.formattedTotal}'
        : (result.hasPhoto
            ? 'Photo attached — enter till total or paste text'
            : 'No total found — enter it manually');
    final store =
        result.storeName.isNotEmpty ? ' · ${result.storeName}' : '';
    final missing = _unmatchedHints.isEmpty
        ? (result.lineHints.isEmpty
            ? ''
            : ' · all line items already on list')
        : ' · ${_unmatchedHints.length} not on list';
    final photo = result.hasPhoto && result.photoByteLength > 0
        ? ' · ${(result.photoByteLength / 1024).ceil()} KB'
        : '';
    _parseHint = '$n$store$missing$photo';
  }

  Future<void> _pickPhoto(ImageSource source) async {
    if (_parsing) return;
    setState(() {
      _parsing = true;
      _parseHint = null;
    });
    try {
      final file = await widget.imagePicker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 2000,
      );
      if (file == null) {
        if (!mounted) return;
        setState(() {
          _parsing = false;
          _parseHint = 'No photo selected';
        });
        return;
      }
      final bytes = await file.readAsBytes();
      final result = await widget.ocr.parseImageBytes(bytes);
      if (!mounted) return;
      setState(() {
        _parsing = false;
        _source = ReceiptSource.ocr;
        _hasPhoto = true;
        _photoByteLength = bytes.length;
        _applyParseResult(
          result.hasPhoto
              ? result
              : ReceiptCapture(
                  totalCents: result.totalCents,
                  storeName: result.storeName,
                  notes: result.notes,
                  rawText: result.rawText,
                  source: ReceiptSource.ocr,
                  lineHints: result.lineHints,
                  hasPhoto: true,
                  photoByteLength: bytes.length,
                ),
          keepPhoto: true,
        );
      });
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() {
        _parsing = false;
        _parseHint = e.code == 'camera_access_denied' ||
                e.code == 'photo_access_denied'
            ? 'Permission denied — allow camera/photos and try again'
            : 'Could not open ${source == ImageSource.camera ? 'camera' : 'gallery'}: ${e.message ?? e.code}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _parsing = false;
        final platform = defaultTargetPlatform;
        final desktopHint = platform == TargetPlatform.windows ||
                platform == TargetPlatform.linux ||
                platform == TargetPlatform.macOS
            ? ' On desktop, try gallery / file pick.'
            : '';
        _parseHint = 'Could not pick photo: $e$desktopHint';
      });
    }
  }

  void _clearPhoto() {
    setState(() {
      _hasPhoto = false;
      _photoByteLength = 0;
      if (_source == ReceiptSource.ocr) {
        _source = _pasteController.text.trim().isNotEmpty
            ? ReceiptSource.pastedText
            : ReceiptSource.manual;
      }
      if (_notesController.text.contains('Photo attached')) {
        _notesController.clear();
      }
      _parseHint = 'Photo removed';
    });
  }

  void _toggleAdd(String name) {
    final key = normalizeReceiptItemName(name);
    setState(() {
      if (_selectedAdds.contains(key)) {
        _selectedAdds.remove(key);
      } else {
        _selectedAdds.add(key);
      }
    });
  }

  void _submit() {
    final total = _parseTotalField();
    if (total == null) {
      setState(() => _parseHint = 'Enter a valid total (e.g. 249.90)');
      return;
    }
    final toAdd = _unmatchedHints
        .where((n) => _selectedAdds.contains(normalizeReceiptItemName(n)))
        .toList();
    var notes = _notesController.text.trim();
    if (_hasPhoto && !notes.toLowerCase().contains('photo')) {
      final kb = _photoByteLength > 0
          ? ' (${(_photoByteLength / 1024).ceil()} KB)'
          : '';
      notes = notes.isEmpty
          ? 'Photo attached$kb'
          : '$notes · Photo attached$kb';
    }
    Navigator.pop(
      context,
      ReceiptCapture(
        totalCents: total,
        storeName: _storeController.text.trim(),
        notes: notes,
        rawText: _pasteController.text.trim(),
        source: _source,
        lineHints: _lineHints,
        itemsToAdd: toAdd,
        hasPhoto: _hasPhoto,
        photoByteLength: _photoByteLength,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final missing = itemsMissingPaidPrice(widget.items);
    final spend = tripSpend(widget.items);

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: ShoppaColors.line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Log receipt',
                style: TextStyle(
                  color: ShoppaColors.ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                missing.isEmpty
                    ? 'Record the till total for this trip'
                    : 'Record the till total — can fill ${missing.length} item'
                        '${missing.length == 1 ? '' : 's'} missing prices',
                style: const TextStyle(color: ShoppaColors.mist, fontSize: 12),
              ),
              if (spend.hasSpend) ...[
                const SizedBox(height: 8),
                Text(
                  'Recorded so far: ${spend.formatted}'
                  '${spend.hasIncompletePricing ? ' (incomplete)' : ''}',
                  style: const TextStyle(
                    color: ShoppaColors.green,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: _totalController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Receipt total',
                  prefixText: 'R ',
                  hintText: '0.00',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _storeController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Store (optional)',
                  hintText: 'e.g. Checkers',
                ),
              ),
              if (widget.suggestedStores.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final store in widget.suggestedStores)
                      ActionChip(
                        label: Text(store),
                        avatar: const Icon(Icons.storefront_outlined, size: 16),
                        onPressed: () {
                          setState(() => _storeController.text = store);
                        },
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _notesController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  hintText: 'Card ending, promo, etc.',
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Receipt photo',
                style: TextStyle(
                  color: ShoppaColors.mist,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _parsing
                          ? null
                          : () => _pickPhoto(ImageSource.camera),
                      icon: const Icon(Icons.photo_camera_outlined, size: 18),
                      label: const Text('Camera'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _parsing
                          ? null
                          : () => _pickPhoto(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_outlined, size: 18),
                      label: const Text('Gallery'),
                    ),
                  ),
                ],
              ),
              if (_hasPhoto) ...[
                const SizedBox(height: 8),
                Material(
                  color: ShoppaColors.green.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                  child: ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.only(left: 12, right: 4),
                    leading: const Icon(
                      Icons.image_outlined,
                      color: ShoppaColors.green,
                    ),
                    title: Text(
                      _photoByteLength > 0
                          ? 'Photo attached (${(_photoByteLength / 1024).ceil()} KB)'
                          : 'Photo attached',
                      style: const TextStyle(
                        color: ShoppaColors.ink,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: const Text(
                      'Enter the till total below if not filled automatically',
                      style: TextStyle(
                        color: ShoppaColors.mist,
                        fontSize: 11,
                      ),
                    ),
                    trailing: IconButton(
                      tooltip: 'Remove photo',
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: _parsing ? null : _clearPhoto,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              const Text(
                'Or paste receipt text',
                style: TextStyle(
                  color: ShoppaColors.mist,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _pasteController,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText:
                      'Paste OCR dump or SMS total…\nTOTAL R249.90',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _parsing ? null : _parsePasted,
                icon: _parsing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.document_scanner_outlined, size: 18),
                label: Text(_parsing ? 'Working…' : 'Parse pasted text'),
              ),
              const SizedBox(height: 6),
              const Text(
                'Auto-OCR from photos is not available yet — attach a photo for '
                'your records, then enter the total or paste text.',
                style: TextStyle(
                  color: ShoppaColors.faint,
                  fontSize: 11,
                ),
              ),
              if (_parseHint != null) ...[
                const SizedBox(height: 8),
                Text(
                  _parseHint!,
                  style: const TextStyle(
                    color: ShoppaColors.amber,
                    fontSize: 12,
                  ),
                ),
              ],
              if (_unmatchedHints.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'On receipt, not on this list'
                  ' (${_selectedAdds.length}/${_unmatchedHints.length} selected)',
                  style: const TextStyle(
                    color: ShoppaColors.mist,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Tap to include impulse buys — added as checked after save',
                  style: TextStyle(color: ShoppaColors.faint, fontSize: 11),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final name in _unmatchedHints)
                      FilterChip(
                        label: Text(name),
                        selected: _selectedAdds
                            .contains(normalizeReceiptItemName(name)),
                        onSelected: (_) => _toggleAdd(name),
                        selectedColor: ShoppaColors.amber.withOpacity(0.25),
                        checkmarkColor: ShoppaColors.amber,
                        labelStyle: const TextStyle(
                          color: ShoppaColors.ink,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _submit,
                icon: const Icon(Icons.receipt_long_outlined),
                label: Text(
                  missing.isEmpty
                      ? 'Save receipt total'
                      : 'Save & suggest missing prices',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
