import 'package:flutter/foundation.dart';

class AppHotkey {
  AppHotkey({required this.id, required this.l10nLabelKey});
  final String id;
  final String l10nLabelKey;
  String? command;
  bool enabled = false;
}

class HotkeyProvider extends ChangeNotifier {
  bool get initialized => true;
  List<AppHotkey> get items => const [];
  AppHotkey getById(String id) => AppHotkey(id: id, l10nLabelKey: id);
  Future<void> initialize() async {}
  Future<void> resetAllToDefaults() async {}
  Future<void> resetToDefault(String id) async {}
  Future<void> clearCommand(String id) async {}
  Future<void> setCommand(String id, String command) async {}
  Future<void> setEnabled(String id, bool value) async {}
  static String formatCommandForDisplay(String? command) => command ?? '';
}
