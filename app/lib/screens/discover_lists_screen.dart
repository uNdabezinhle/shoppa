import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/api_client.dart';
import '../core/lists_repository.dart';
import '../theme/shoppa_theme.dart';

/// FR-8.2 — discover and clone published public lists.
class DiscoverListsScreen extends StatefulWidget {
  const DiscoverListsScreen({super.key, required this.listsRepository});

  final ListsRepository listsRepository;

  @override
  State<DiscoverListsScreen> createState() => _DiscoverListsScreenState();
}

class _DiscoverListsScreenState extends State<DiscoverListsScreen> {
  late Future<List<ShoppaList>> _lists;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _lists = widget.listsRepository.fetchPublicLists();
    });
  }

  Future<void> _clone(ShoppaList list) async {
    try {
      final clone = await widget.listsRepository.duplicateList(list.id);
      if (!mounted) return;
      context.push(
        '/lists/${clone.id}?title=${Uri.encodeComponent(clone.title)}',
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: ShoppaColors.rose),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not clone list: $e'),
          backgroundColor: ShoppaColors.rose,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Discover lists')),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: FutureBuilder<List<ShoppaList>>(
          future: _lists,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        snapshot.error is ApiException
                            ? (snapshot.error as ApiException).message
                            : 'Could not load public lists.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: ShoppaColors.rose),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _reload,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              );
            }
            final lists = snapshot.data!;
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (lists.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: Center(
                      child: Text(
                        'No published lists yet — Professional users can publish lists publicly.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: ShoppaColors.mist),
                      ),
                    ),
                  )
                else
                  ...lists.map(
                    (list) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        tileColor: ShoppaColors.panel,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: const BorderSide(color: ShoppaColors.line),
                        ),
                        title: Text(
                          list.title,
                          style: const TextStyle(
                            color: ShoppaColors.ink,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          '${list.category} · ${list.itemCount} items',
                          style: const TextStyle(color: ShoppaColors.mist, fontSize: 12),
                        ),
                        trailing: TextButton(
                          onPressed: () => _clone(list),
                          child: const Text('Clone'),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}