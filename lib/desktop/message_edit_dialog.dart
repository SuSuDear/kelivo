import 'package:flutter/material.dart';
import '../features/chat/models/message_edit_result.dart';
import '../core/models/chat_message.dart';
import '../features/chat/widgets/message_edit_sheet.dart';

Future<MessageEditResult?> showMessageEditDesktopDialog(
  BuildContext context, {
  required ChatMessage message,
}) {
  return showMessageEditSheet(context, message: message);
}
