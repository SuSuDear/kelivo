import 'package:flutter/material.dart';
import '../features/chat/pages/html_preview_page.dart';

Future<void> showHtmlPreviewDesktopDialog(
  BuildContext context, {
  required String html,
}) async {
  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => HtmlPreviewPage(html: html)),
  );
}
