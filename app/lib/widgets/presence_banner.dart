import 'package:flutter/material.dart';

import '../theme/shoppa_theme.dart';

class PresenceBanner extends StatelessWidget {
  const PresenceBanner({
    super.key,
    required this.editorEmails,
    this.connected = true,
  });

  final List<String> editorEmails;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    if (editorEmails.isEmpty && connected) return const SizedBox.shrink();

    final text = editorEmails.isEmpty
        ? 'Reconnecting to live updates…'
        : editorEmails.length == 1
            ? '${_displayName(editorEmails.first)} is editing this list now'
            : '${editorEmails.length} collaborators are editing this list now';

    return Container(
      width: double.infinity,
      color: ShoppaColors.panel2.withOpacity(0.6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: connected ? ShoppaColors.green : ShoppaColors.amber,
              shape: BoxShape.circle,
              boxShadow: connected
                  ? [BoxShadow(color: ShoppaColors.green.withOpacity(0.6), blurRadius: 6)]
                  : null,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: connected ? ShoppaColors.mist : ShoppaColors.amber,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _displayName(String email) {
    final local = email.split('@').first;
    if (local.contains('.')) {
      return local.split('.').map((p) => p.isEmpty ? p : '${p[0].toUpperCase()}${p.substring(1)}').join(' ');
    }
    return local[0].toUpperCase() + local.substring(1);
  }
}