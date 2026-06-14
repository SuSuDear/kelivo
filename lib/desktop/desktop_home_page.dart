import 'package:flutter/material.dart';
import '../features/home/pages/home_page.dart';
class DesktopHomePage extends StatelessWidget {
  const DesktopHomePage({super.key, this.initialSettingsPane, this.initialProviderId});
  final Object? initialSettingsPane;
  final String? initialProviderId;
  @override
  Widget build(BuildContext context) => const HomePage();
}
