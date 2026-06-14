import 'package:flutter/material.dart';

class DesktopContextMenuItem {
  const DesktopContextMenuItem({required this.label, this.icon, this.onTap, this.enabled = true, this.destructive = false});
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool enabled;
  final bool destructive;
}

Future<void> showDesktopContextMenuAt(BuildContext context, {required Offset globalPosition, required List<DesktopContextMenuItem> items}) async {
  final available = items.where((e) => e.enabled).toList();
  if (available.isEmpty) return;
  await showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: available.map((item) => ListTile(
          leading: item.icon == null ? null : Icon(item.icon),
          title: Text(item.label),
          textColor: item.destructive ? Theme.of(ctx).colorScheme.error : null,
          onTap: () { Navigator.of(ctx).pop(); item.onTap?.call(); },
        )).toList(),
      ),
    ),
  );
}

Future<void> showDesktopAnchoredMenu(BuildContext context, {required GlobalKey anchorKey, required List<DesktopContextMenuItem> items}) =>
    showDesktopContextMenuAt(context, globalPosition: Offset.zero, items: items);
