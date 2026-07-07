import 'package:flutter/material.dart';

import '../core/lists_repository.dart';
import '../theme/shoppa_theme.dart';

const _avatarColors = [
  ShoppaColors.blue,
  ShoppaColors.violet,
  ShoppaColors.green,
  ShoppaColors.amber,
];

class CollaboratorAvatarStack extends StatelessWidget {
  const CollaboratorAvatarStack({
    super.key,
    required this.collaborators,
    this.size = 24,
    this.maxVisible = 4,
  });

  final List<ShoppaCollaboratorPreview> collaborators;
  final double size;
  final int maxVisible;

  @override
  Widget build(BuildContext context) {
    if (collaborators.isEmpty) return const SizedBox.shrink();
    final visible = collaborators.take(maxVisible).toList();
    return SizedBox(
      width: size + (visible.length - 1) * (size * 0.55),
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < visible.length; i++)
            Positioned(
              left: i * size * 0.55,
              child: _AvatarCircle(
                initials: visible[i].initials,
                color: _avatarColors[i % _avatarColors.length],
                size: size,
              ),
            ),
        ],
      ),
    );
  }
}

class _AvatarCircle extends StatelessWidget {
  const _AvatarCircle({
    required this.initials,
    required this.color,
    required this.size,
  });

  final String initials;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withOpacity(0.22),
        shape: BoxShape.circle,
        border: Border.all(color: ShoppaColors.panel, width: 2),
      ),
      child: Text(
        initials,
        style: TextStyle(
          color: color,
          fontSize: size * 0.34,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}