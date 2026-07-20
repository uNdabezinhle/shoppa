import 'package:flutter/material.dart';

import '../core/list_text_format.dart';
import '../core/lists_repository.dart';
import '../theme/shoppa_theme.dart';

/// How the formatted list text should leave the app.
enum ListTextExportAction { copy, share }

/// Result of [showCopyListTextSheet].
class ListTextExportResult {
  const ListTextExportResult({
    required this.options,
    required this.action,
  });

  final ListTextFormatOptions options;
  final ListTextExportAction action;
}

/// Pick format, then copy or open the system share sheet.
Future<ListTextExportResult?> showCopyListTextSheet(
  BuildContext context, {
  required ShoppaList list,
}) {
  return showModalBottomSheet<ListTextExportResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: ShoppaColors.panel,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _CopyListTextSheet(list: list),
  );
}

class _CopyListTextSheet extends StatefulWidget {
  const _CopyListTextSheet({required this.list});

  final ShoppaList list;

  @override
  State<_CopyListTextSheet> createState() => _CopyListTextSheetState();
}

class _CopyListTextSheetState extends State<_CopyListTextSheet> {
  bool _includeChecked = true;
  bool _checkboxStyle = true;
  bool _groupByAisle = false;
  bool _includePrices = false;
  bool _checkedOnly = false;

  ListTextFormatOptions get _options => ListTextFormatOptions(
        includeChecked: _includeChecked,
        checkboxStyle: _checkboxStyle,
        groupByAisle: _groupByAisle,
        includePrices: _includePrices,
        checkedOnly: _checkedOnly,
      );

  String get _preview {
    final text = formatListAsText(widget.list, options: _options);
    if (text.length <= 280) return text;
    return '${text.substring(0, 280)}…';
  }

  void _finish(ListTextExportAction action) {
    Navigator.pop(
      context,
      ListTextExportResult(options: _options, action: action),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
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
                'Share as text',
                style: TextStyle(
                  color: ShoppaColors.ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Send via WhatsApp, Messages, email — or copy to paste later',
                style: TextStyle(color: ShoppaColors.mist, fontSize: 12),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ActionChip(
                    label: const Text('Shopping share'),
                    avatar: const Icon(Icons.shopping_cart_outlined, size: 16),
                    onPressed: () {
                      setState(() {
                        _includeChecked = false;
                        _checkboxStyle = false;
                        _groupByAisle = true;
                        _includePrices = false;
                        _checkedOnly = false;
                      });
                    },
                  ),
                  ActionChip(
                    label: const Text('Full checklist'),
                    avatar: const Icon(Icons.checklist, size: 16),
                    onPressed: () {
                      setState(() {
                        _includeChecked = true;
                        _checkboxStyle = true;
                        _groupByAisle = false;
                        _includePrices = false;
                        _checkedOnly = false;
                      });
                    },
                  ),
                  ActionChip(
                    label: const Text('Trip recap'),
                    avatar: const Icon(Icons.receipt_long_outlined, size: 16),
                    onPressed: () {
                      setState(() {
                        _includeChecked = true;
                        _checkboxStyle = false;
                        _groupByAisle = false;
                        _includePrices = true;
                        _checkedOnly = true;
                      });
                    },
                  ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Checked items only'),
                value: _checkedOnly,
                onChanged: (v) => setState(() {
                  _checkedOnly = v;
                  if (v) _includeChecked = true;
                }),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Include checked items'),
                value: _includeChecked,
                onChanged: _checkedOnly
                    ? null
                    : (v) => setState(() => _includeChecked = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Checkbox style [ ] / [x]'),
                value: _checkboxStyle,
                onChanged: (v) => setState(() => _checkboxStyle = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Group by aisle'),
                value: _groupByAisle,
                onChanged: (v) => setState(() => _groupByAisle = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Include paid prices'),
                value: _includePrices,
                onChanged: (v) => setState(() => _includePrices = v),
              ),
              const SizedBox(height: 8),
              const Text(
                'Preview',
                style: TextStyle(
                  color: ShoppaColors.mist,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 160),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: ShoppaColors.panel2,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: ShoppaColors.line),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    _preview,
                    style: const TextStyle(
                      color: ShoppaColors.ink,
                      fontSize: 12,
                      height: 1.35,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => _finish(ListTextExportAction.share),
                icon: const Icon(Icons.share_outlined),
                label: const Text('Share…'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _finish(ListTextExportAction.copy),
                icon: const Icon(Icons.copy_all_outlined),
                label: const Text('Copy to clipboard'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
