import 'package:flutter/material.dart';
import '../core/models/chat_message.dart';

class MessageEditResult {
  const MessageEditResult({required this.text, this.saveOnly = false});
  final String text;
  final bool saveOnly;
}
Future<MessageEditResult?> showMessageEditDesktopDialog(BuildContext context, {required ChatMessage message}) async => null;
