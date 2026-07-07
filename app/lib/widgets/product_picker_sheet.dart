import 'package:flutter/material.dart';

import '../core/catalogue_repository.dart';
import '../theme/shoppa_theme.dart';

/// Search-and-select a catalogue product, or skip for free-text entry.
Future<ShoppaProduct?> showProductPickerSheet(
  BuildContext context, {
  required CatalogueRepository catalogueRepository,
}) {
  return showModalBottomSheet<ShoppaProduct>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _ProductPickerSheet(catalogueRepository: catalogueRepository),
  );
}

class _ProductPickerSheet extends StatefulWidget {
  const _ProductPickerSheet({required this.catalogueRepository});

  final CatalogueRepository catalogueRepository;

  @override
  State<_ProductPickerSheet> createState() => _ProductPickerSheetState();
}

class _ProductPickerSheetState extends State<_ProductPickerSheet> {
  final _searchController = TextEditingController();
  Future<List<ShoppaProduct>>? _results;
  String? _error;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _search([String? query]) {
    final q = query ?? _searchController.text;
    setState(() {
      _error = null;
      _results = widget.catalogueRepository.searchProducts(q);
    });
  }

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Add from catalogue',
            style: TextStyle(
              color: ShoppaColors.ink,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Search products…',
              prefixIcon: Icon(Icons.search),
            ),
            onSubmitted: _search,
            onChanged: (v) {
              if (v.length >= 2 || v.isEmpty) _search(v);
            },
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: ShoppaColors.rose)),
          ],
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: FutureBuilder<List<ShoppaProduct>>(
              future: _results,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Text(
                    'Search failed: ${snapshot.error}',
                    style: const TextStyle(color: ShoppaColors.rose),
                  );
                }
                final products = snapshot.data ?? [];
                if (products.isEmpty) {
                  return const Text(
                    'No matching products.',
                    style: TextStyle(color: ShoppaColors.mist),
                  );
                }
                return ListView.separated(
                  shrinkWrap: true,
                  itemCount: products.length,
                  separatorBuilder: (_, __) => const Divider(height: 12),
                  itemBuilder: (context, index) {
                    final product = products[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        product.name,
                        style: const TextStyle(color: ShoppaColors.ink),
                      ),
                      subtitle: Text(
                        product.region,
                        style: const TextStyle(
                          color: ShoppaColors.mist,
                          fontSize: 12,
                        ),
                      ),
                      onTap: () => Navigator.pop(context, product),
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Skip — add free-text item'),
          ),
        ],
      ),
    );
  }
}