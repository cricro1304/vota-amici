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
        AvatarSize.md => 20,
        AvatarSize.lg => 28,
      };

  String get _initials {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '??';
    return trimmed
        .substring(0, trimmed.length >= 2 ? 2 : 1)
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final bg = playerColor(index);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      width: _dim,
      height: _dim,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: selected
            ? Border.all(color: Colors.white, width: 4)
            : null,
        boxShadow: isWinner
            ? kWinnerGlow
            : [
                BoxShadow(
                  color: bg.withValues(alpha: 0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      alignment: Alignment.center,
      child: Text(
        _initials,
        style: displayFont(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: _fontSize,
        ),
      ),
    );
  }
}
