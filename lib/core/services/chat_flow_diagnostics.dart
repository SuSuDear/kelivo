import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../utils/app_directories.dart';

class ChatFlowDiagnostics {
  ChatFlowDiagnostics._();

  static bool _active = false;
  static String? _flowId;
  static Future<void> _queue = Future<void>.value();

  static bool get active => _active;
  static String? get flowId => _flowId;

  static String start({
    required String conversationId,
    required String messageId,
    required String providerId,
    required String modelId,
    required bool stream,
    required bool useResponsesApi,
  }) {
    final id = '${DateTime.now().millisecondsSinceEpoch}-$messageId';
    _active = true;
    _flowId = id;
    log(
      'FLOW_START id=$id conversation=$conversationId message=$messageId '
      'provider=$providerId model=$modelId stream=$stream responses=$useResponsesApi',
    );
    return id;
  }

  static void end(String reason) {
    log('FLOW_END reason=${escape(reason)}');
    _active = false;
    _flowId = null;
  }

  static void log(String line) {
    if (!_active && !line.startsWith('FLOW_START')) return;
    final now = DateTime.now();
    final stamp = _formatTs(now);
    final id = _flowId ?? '-';
    final text = '[$stamp] [flow:$id] $line\n';
    _queue = _queue.then((_) async {
      try {
        final dir = await AppDirectories.getAppDataDirectory();
        final logsDir = Directory('${dir.path}/logs');
        if (!await logsDir.exists()) await logsDir.create(recursive: true);
        final file = File('${logsDir.path}/chat_flow.txt');
        await file.writeAsString(text, mode: FileMode.append, flush: true);
      } catch (_) {}
    });
  }


  static void trace(String line) {
    if (!_active && !line.startsWith('FLOW_START')) return;
    final now = DateTime.now();
    final stamp = _formatTs(now);
    final id = _flowId ?? '-';
    final text = '[$stamp] [flow:$id] $line\n';
    _queue = _queue.then((_) async {
      try {
        final dir = await AppDirectories.getAppDataDirectory();
        final logsDir = Directory('${dir.path}/logs');
        if (!await logsDir.exists()) await logsDir.create(recursive: true);
        final file = File('${logsDir.path}/chat_stream_trace.txt');
        await file.writeAsString(text, mode: FileMode.append, flush: true);
      } catch (_) {}
    });
  }

  static String summarizeChunk(String text, {int max = 500}) {
    final escaped = escape(text);
    if (escaped.length <= max) return escaped;
    return '${escaped.substring(0, max)}...(len=${escaped.length})';
  }

  static String summarizeObject(Object? value, {int max = 800}) {
    String raw;
    try {
      raw = const JsonEncoder.withIndent('  ').convert(value);
    } catch (_) {
      raw = value?.toString() ?? '';
    }
    return summarizeChunk(raw, max: max);
  }

  static String escape(String input) => input
      .replaceAll('\\', r'\\')
      .replaceAll('\r', r'\r')
      .replaceAll('\n', r'\n')
      .replaceAll('\t', r'\t');

  static String _two(int v) => v.toString().padLeft(2, '0');
  static String _formatTs(DateTime dt) =>
      '${dt.year}-${_two(dt.month)}-${_two(dt.day)} '
      '${_two(dt.hour)}:${_two(dt.minute)}:${_two(dt.second)}.'
      '${dt.millisecond.toString().padLeft(3, '0')}';
}
