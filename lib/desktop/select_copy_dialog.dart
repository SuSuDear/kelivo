import 'package:flutter/material.dart';
import '../core/models/chat_message.dart';
import '../features/chat/widgets/select_copy_sheet.dart';

Future<void> showSelectCopyDesktopDialog(
  BuildContext context, {
  required ChatMessage message,
}) async {
  await showSelectCopySheet(context, message: message);
}
