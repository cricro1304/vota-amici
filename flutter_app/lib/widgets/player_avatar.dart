import 'package:flutter/material.dart';

import '../core/theme.dart';

enum AvatarSize { sm, md, lg }

class PlayerAvatar extends StatelessWidget {
  const PlayerAvatar({
    super.key,
    required this.name,
    required this.index,
    this.size = AvatarSize.md,
    this.selected = false,
    this.isWinner = false,
  });

  final String name;
  final int index;
  final AvatarSize size;
  final bool selected;
  final bool isWinner;

  double get _dim => switch (size) {
        AvatarSize.sm => 40,
        AvatarSize.md => 56,
        AvatarSize.lg => 80,
      };

  double get _fontSize => switch (size) {
        AvatarSize.sm => 14,
        AvatarSize.md => 18,
        AvatarSize.lg => 26,
      };

  String get _initials {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '??';
    return trimmed.substring(0, trimmed.length >= 2 ? 2 : 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final bg = playerColor(index);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: _dim,
      height: _dim,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: selected
            ? Border.all(
                color: Theme.of(context).colorScheme.primary,
                width: 4,
              )
            : null,
        boxShadow: isWinner
            ? [
                BoxShadow(
                  color: Colors.amber.withValues(alpha: 0.7),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      alignment: Alignment.center,
      child: Text(
        _initials,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: _fontSize,
        ),
      ),
    );
  }
}
