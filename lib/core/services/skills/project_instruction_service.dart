import 'dart:io';

import 'package:path/path.dart' as p;

/// Loads project-level agent instructions near paths mentioned by the user.
///
/// This mirrors Codex's AGENTS.md behavior at a small scale: when a user mentions
/// a local project path, scan that directory and its parents for AGENTS.md and
/// SKILL.md/skill.md, then inject the matching files as project instructions.
class ProjectInstructionService {
  static const int _maxFiles = 6;
  static const int _maxCharsPerFile = 30000;
  static const int _maxTotalChars = 80000;

  static Future<String> buildPromptForUserMessage(String userMessage) async {
    final files = _findInstructionFiles(userMessage);
    if (files.isEmpty) return '';

    var total = 0;
    final buffer = StringBuffer()
      ..writeln('## Project instructions')
      ..writeln(
        'The following local project instruction files were found near paths mentioned by the user. Treat AGENTS.md as repository-level guidance and SKILL.md/skill.md as project-level skill instructions for that project.',
      );

    for (final file in files.take(_maxFiles)) {
      try {
        var content = await file.readAsString();
        if (content.length > _maxCharsPerFile) {
          content = '${content.substring(0, _maxCharsPerFile)}\n\n[project instruction truncated]';
        }
        if (total + content.length > _maxTotalChars) break;
        total += content.length;
        buffer
          ..writeln('<project-instructions path="${file.path}">')
          ..writeln(content.trim())
          ..writeln('</project-instructions>');
      } catch (_) {}
    }

    return buffer.toString().trim();
  }

  static List<File> _findInstructionFiles(String text) {
    final dirs = _candidateDirectories(text);
    if (dirs.isEmpty) return const <File>[];

    final seen = <String>{};
    final files = <File>[];
    for (final dir in dirs) {
      var current = dir.absolute;
      for (var depth = 0; depth < 8; depth++) {
        for (final name in const <String>[
          'AGENTS.md',
          'agents.md',
          'SKILL.md',
          'skill.md',
        ]) {
          final file = File(p.join(current.path, name));
          if (file.existsSync() && seen.add(file.path)) {
            files.add(file);
          }
        }
        final parent = current.parent;
        if (parent.path == current.path) break;
        current = parent;
      }
    }
    return files;
  }

  static List<Directory> _candidateDirectories(String text) {
    final dirs = <Directory>[];
    final seen = <String>{};
    final pathPattern = RegExp(r'(/[^\s`"<>|]+)');
    for (final match in pathPattern.allMatches(text)) {
      var raw = match.group(1) ?? '';
      raw = raw.replaceAll(RegExp(r'[,.;:)\]}]+$'), '');
      if (raw.isEmpty) continue;
      final entityType = FileSystemEntity.typeSync(raw, followLinks: true);
      Directory? dir;
      if (entityType == FileSystemEntityType.directory) {
        dir = Directory(raw);
      } else if (entityType == FileSystemEntityType.file) {
        dir = File(raw).parent;
      }
      if (dir == null) continue;
      final key = dir.absolute.path;
      if (seen.add(key)) dirs.add(dir.absolute);
    }
    return dirs;
  }
}
