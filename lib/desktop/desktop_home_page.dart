import 'package:flutter/material.dart';
import '../features/home/pages/home_page.dart';

class DesktopHomePage extends StatelessWidget {
  const DesktopHomePage({
    super.key,
    this.initialSettingsSection,
    this.initialProviderKey,
    this.initialTabIndex,
  });
  final String? initialSettingsSection;
  final String? initialProviderKey;
  final int? initialTabIndex;
  @override
  Widget build(BuildContext context) => const HomePage();
}
