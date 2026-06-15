import 'package:flutter/material.dart';

class DesktopContextMenuItem {
  final IconData? icon;
  final String? svgAsset;
  final String label;
  final VoidCallback? onTap;
  final bool danger;

  const DesktopContextMenuItem({
    this.icon,
    this.svgAsset,
    required this.label,
    this.onTap,
    this.danger = false,
  });
}

Future<void> showDesktopContextMenuAt(
  BuildContext context, {
  required Offset globalPosition,
  required List<DesktopContextMenuItem> items,
}) async {
  if (items.isNotEmpty) items.first.onTap?.call();
}

Future<void> showDesktopAnchoredMenu(
  BuildContext context, {
  required GlobalKey anchorKey,
  required List<DesktopContextMenuItem> items,
  Offset offset = Offset.zero,
}) async {
  if (items.isNotEmpty) items.first.onTap?.call();
}
