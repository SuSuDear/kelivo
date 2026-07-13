import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../../utils/app_directories.dart';

/// Codex-style user-installed skill metadata.
class BuiltInSkill {
  const BuiltInSkill({
    required this.name,
    required this.description,
    required this.directoryPath,
    this.directoryName,
  });

  /// Display and invocation name. Prefer the `name:` value from SKILL.md.
  final String name;
  final String description;
  final String directoryPath;

  /// Installed directory name kept as a backwards-compatible alias.
  final String? directoryName;

  String get sourcePath => directoryPath;

  String get installedName {
    final value = directoryName?.trim();
    if (value != null && value.isNotEmpty) return value;
    return p.basename(directoryPath);
  }

  Iterable<String> get matchNames sync* {
    final primary = name.trim();
    if (primary.isNotEmpty) yield primary;
    final installed = installedName.trim();
    if (installed.isNotEmpty && installed.toLowerCase() != primary.toLowerCase()) {
      yield installed;
    }
  }

  bool matchesName(String value) {
    final key = value.trim().toLowerCase();
    if (key.isEmpty) return false;
    return matchNames.any((name) => name.trim().toLowerCase() == key);
  }
}

/// Loads user-installed Codex-style skills from the app data skills directory.
class BuiltInSkillService {
  static const int _maxSkillContentChars = 50000;
  static const int _maxResourceBytes = 12000;
  static const int _maxTotalResourceBytes = 64000;
  static const int _maxResourceFiles = 20;

  static List<BuiltInSkill>? _catalogCache;
  static final Map<String, String> _contentCache = <String, String>{};
  static final Map<String, String> _resourceCache = <String, String>{};

  static Future<Directory> userSkillsDirectory() async {
    final root = await AppDirectories.getAppDataDirectory();
    return Directory(p.join(root.path, 'skills'));
  }

  static void clearCache() {
    _catalogCache = null;
    _contentCache.clear();
    _resourceCache.clear();
  }

  static Future<List<BuiltInSkill>> loadCatalog({
    AssetBundle? bundle,
    bool refresh = false,
  }) async {
    if (!refresh && _catalogCache != null) return _catalogCache!;
    final catalog = await _loadUserCatalog();
    catalog.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final readonly = List<BuiltInSkill>.unmodifiable(catalog);
    _catalogCache = readonly;
    return readonly;
  }

  static Future<BuiltInSkill> installFromDirectory(
    String sourcePath, {
    bool overwrite = false,
  }) async {
    final source = Directory(sourcePath.trim()).absolute;
    if (!await source.exists()) {
      throw ArgumentError('Skill directory does not exist: ${source.path}');
    }

    final skillFile = _findSkillFileInDirectory(source);
    if (skillFile == null || !await skillFile.exists()) {
      throw ArgumentError('Skill directory must contain SKILL.md');
    }

    final root = await userSkillsDirectory();
    if (!await root.exists()) await root.create(recursive: true);

    final baseName = _sanitizeSkillName(p.basename(source.path));
    final name = baseName.isEmpty
        ? 'skill-${DateTime.now().millisecondsSinceEpoch}'
        : baseName;
    var target = Directory(p.join(root.path, name));
    if (await target.exists()) {
      if (overwrite) {
        await target.delete(recursive: true);
      } else {
        target = Directory(
          p.join(root.path, '$name-${DateTime.now().millisecondsSinceEpoch}'),
        );
      }
    }

    await _copyDirectory(source, target);
    clearCache();

    final content = await skillFile.readAsString();
    final installedName = p.basename(target.path);
    return BuiltInSkill(
      name: _nameFromSkillMarkdown(content, installedName),
      description: _descriptionFromSkillMarkdown(content),
      directoryPath: target.path,
      directoryName: installedName,
    );
  }

  static Future<BuiltInSkill> installFromSkillFile(
    String skillFilePath, {
    bool overwrite = false,
  }) async {
    final sourceFile = File(skillFilePath.trim()).absolute;
    if (!await sourceFile.exists()) {
      throw ArgumentError('SKILL.md file does not exist: ${sourceFile.path}');
    }
    final sourceSegments = sourceFile.parent.uri.pathSegments
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    final name = _sanitizeSkillName(
      sourceSegments.isNotEmpty
          ? sourceSegments.last
          : p.basename(sourceFile.parent.path),
    );
    final root = await userSkillsDirectory();
    if (!await root.exists()) await root.create(recursive: true);
    final dirName = name.isEmpty
        ? 'skill-${DateTime.now().millisecondsSinceEpoch}'
        : name;
    var target = Directory(p.join(root.path, dirName));
    if (await target.exists()) {
      if (overwrite) {
        await target.delete(recursive: true);
      } else {
        target = Directory(
          p.join(root.path, '$dirName-${DateTime.now().millisecondsSinceEpoch}'),
        );
      }
    }
    await target.create(recursive: true);
    await sourceFile.copy(p.join(target.path, 'SKILL.md'));
    clearCache();
    final content = await sourceFile.readAsString();
    final installedName = p.basename(target.path);
    return BuiltInSkill(
      name: _nameFromSkillMarkdown(content, installedName),
      description: _descriptionFromSkillMarkdown(content),
      directoryPath: target.path,
      directoryName: installedName,
    );
  }

  static Future<BuiltInSkill> installFromZipFile(
    String zipFilePath, {
    bool overwrite = false,
  }) async {
    final zipFile = File(zipFilePath.trim()).absolute;
    if (!await zipFile.exists()) {
      throw ArgumentError('Zip file does not exist: ${zipFile.path}');
    }
    final bytes = await zipFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes, verify: false);
    final skillEntries = archive.files.where((e) {
      final normalized = e.name.replaceAll('\\', '/');
      return normalized.toLowerCase().endsWith('/skill.md') ||
          normalized.toLowerCase() == 'skill.md';
    }).toList(growable: false);
    if (skillEntries.isEmpty) {
      throw ArgumentError('Zip package must contain SKILL.md');
    }
    final normalized = skillEntries.first.name.replaceAll('\\', '/');
    final rootPrefix = normalized.toLowerCase() == 'skill.md'
        ? ''
        : normalized.substring(0, normalized.length - 'SKILL.md'.length);
    final sourceName = _sanitizeSkillName(
      rootPrefix.isEmpty
          ? p.basenameWithoutExtension(zipFile.path)
          : rootPrefix.split('/').where((e) => e.isNotEmpty).last,
    );
    final root = await userSkillsDirectory();
    if (!await root.exists()) await root.create(recursive: true);
    final dirName = sourceName.isEmpty
        ? 'skill-${DateTime.now().millisecondsSinceEpoch}'
        : sourceName;
    var target = Directory(p.join(root.path, dirName));
    if (await target.exists()) {
      if (overwrite) {
        await target.delete(recursive: true);
      } else {
        target = Directory(
          p.join(root.path, '$dirName-${DateTime.now().millisecondsSinceEpoch}'),
        );
      }
    }
    await target.create(recursive: true);

    for (final entry in archive.files) {
      final entryPath = entry.name.replaceAll('\\', '/');
      String relative;
      if (rootPrefix.isNotEmpty) {
        if (!entryPath.startsWith(rootPrefix)) continue;
        relative = entryPath.substring(rootPrefix.length);
      } else {
        relative = entryPath;
      }
      final parts = relative
          .split('/')
          .where((seg) => seg.isNotEmpty && seg != '.' && seg != '..')
          .toList(growable: false);
      if (parts.isEmpty) continue;
      final outPath = p.joinAll(<String>[target.path, ...parts]);
      if (entry.isFile) {
        File(outPath).parent.createSync(recursive: true);
        final output = OutputFileStream(outPath);
        try {
          entry.writeContent(output);
        } finally {
          output.closeSync();
        }
      } else {
        await Directory(outPath).create(recursive: true);
      }
    }
    final installedSkillFile = _findSkillFileInDirectory(target);
    if (installedSkillFile == null || !await installedSkillFile.exists()) {
      throw ArgumentError('Zip package extracted but SKILL.md was not installed');
    }
    clearCache();
    final content = await installedSkillFile.readAsString();
    final installedName = p.basename(target.path);
    return BuiltInSkill(
      name: _nameFromSkillMarkdown(content, installedName),
      description: _descriptionFromSkillMarkdown(content),
      directoryPath: target.path,
      directoryName: installedName,
    );
  }

  static Future<String> buildPromptForUserMessage(
    String userMessage, {
    List<String> activeSkillNames = const <String>[],
    AssetBundle? bundle,
  }) async {
    final catalog = await loadCatalog();
    final installDir = await userSkillsDirectory();
    if (catalog.isEmpty && !_looksSkillRelated(userMessage)) return '';

    final conversation = _findNamedSkills(activeSkillNames, catalog);
    final explicit = _findExplicitlyInvokedSkills(userMessage, catalog);
    final implicit = explicit.isEmpty && conversation.isEmpty
        ? _findImplicitlyMatchedSkills(userMessage, catalog)
        : const <BuiltInSkill>[];
    final loaded = _dedupeSkills(<BuiltInSkill>[
      ...conversation,
      ...explicit,
      ...implicit,
    ]);

    final buffer = StringBuffer()
      ..writeln('## Skills')
      ..writeln(
        'The app provides Codex-style user-installed skills. A skill is a directory with a SKILL.md file plus optional resources such as scripts, references, templates, examples, or fixtures. Full SKILL.md instructions are loaded when explicitly invoked, enabled for the current conversation, or implicitly matched with high confidence.',
      )
      ..writeln('User-installed skills directory: ${installDir.path}')
      ..writeln(
        'Manual install rule: copy each skill directory that contains SKILL.md into the user-installed skills directory above. The app discovers immediate subdirectories as installed skills.',
      );

    if (catalog.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Available skills:');
      for (final skill in catalog) {
        final description = skill.description.isEmpty
            ? 'No description provided.'
            : skill.description;
        buffer.writeln('- ${skill.name}: $description');
      }
    }

    if (loaded.isEmpty) {
      if (catalog.isNotEmpty) {
        buffer
          ..writeln()
          ..writeln(
            'To load a skill for one message, explicitly invoke it with `\$skill-name`, `/skill-name`, `/skill skill-name`, or `/skills skill-name`. Use the Skills button to enable a skill for the current conversation.',
          );
      }
      return buffer.toString().trim();
    }

    buffer
      ..writeln()
      ..writeln('Loaded skill instructions:');

    for (final skill in loaded) {
      final trigger = conversation.contains(skill)
          ? 'conversation'
          : (explicit.contains(skill) ? 'explicit' : 'implicit');
      final content = await _loadSkillContent(skill);
      final resources = await _loadSkillResources(skill);
      if (content.trim().isEmpty && resources.trim().isEmpty) continue;
      buffer
        ..writeln(
          '<skill name="${skill.name}" source="${skill.sourcePath}" trigger="$trigger">',
        );
      if (content.trim().isNotEmpty) {
        buffer
          ..writeln('<skill-md>')
          ..writeln(content.trim())
          ..writeln('</skill-md>');
      }
      if (resources.trim().isNotEmpty) {
        buffer.writeln(resources.trim());
      }
      buffer.writeln('</skill>');
    }

    return buffer.toString().trim();
  }

  static Future<List<BuiltInSkill>> _loadUserCatalog() async {
    try {
      final root = await userSkillsDirectory();
      if (!await root.exists()) return const <BuiltInSkill>[];
      final catalog = <BuiltInSkill>[];
      for (final entity in root.listSync(followLinks: false)) {
        if (entity is! Directory) continue;
        final skillFile = _findSkillFileInDirectory(entity);
        if (skillFile == null || !skillFile.existsSync()) continue;
        String content = '';
        try {
          content = skillFile.readAsStringSync();
        } catch (_) {}
        final installedName = p.basename(entity.path);
        catalog.add(
          BuiltInSkill(
            name: _nameFromSkillMarkdown(content, installedName),
            description: _descriptionFromSkillMarkdown(content),
            directoryPath: entity.path,
            directoryName: installedName,
          ),
        );
      }
      return catalog;
    } catch (_) {
      return const <BuiltInSkill>[];
    }
  }

  static Future<String> _loadSkillContent(BuiltInSkill skill) async {
    final cacheKey = 'content:${skill.sourcePath}';
    if (_contentCache.containsKey(cacheKey)) return _contentCache[cacheKey]!;

    var content = '';
    final skillFile = _findSkillFileInDirectory(Directory(skill.directoryPath));
    if (skillFile != null) {
      try {
        content = await skillFile.readAsString();
      } catch (_) {}
    }

    if (content.length > _maxSkillContentChars) {
      content = '${content.substring(0, _maxSkillContentChars)}\n\n[SKILL.md truncated]';
    }
    _contentCache[cacheKey] = content;
    return content;
  }

  static Future<String> _loadSkillResources(BuiltInSkill skill) async {
    final cacheKey = 'resources:${skill.sourcePath}';
    if (_resourceCache.containsKey(cacheKey)) return _resourceCache[cacheKey]!;

    final dir = Directory(skill.directoryPath);
    if (!await dir.exists()) return '';

    final files = <File>[];
    try {
      for (final entity in dir.listSync(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final rel = p.relative(entity.path, from: dir.path);
        if (rel == 'SKILL.md' || rel == 'skill.md') continue;
        if (!_shouldIncludeResource(rel)) continue;
        files.add(entity);
      }
    } catch (_) {}
    files.sort((a, b) => a.path.compareTo(b.path));

    var total = 0;
    var count = 0;
    final buffer = StringBuffer();
    for (final file in files) {
      if (count >= _maxResourceFiles || total >= _maxTotalResourceBytes) break;
      final rel = p.relative(file.path, from: dir.path);
      try {
        final length = await file.length();
        if (length > _maxResourceBytes) continue;
        final content = await file.readAsString();
        total += content.length;
        count++;
        if (buffer.isEmpty) buffer.writeln('<skill-resources>');
        buffer
          ..writeln('<resource path="$rel">')
          ..writeln(content.trimRight())
          ..writeln('</resource>');
      } catch (_) {}
    }
    if (buffer.isNotEmpty) buffer.writeln('</skill-resources>');
    final resources = buffer.toString().trim();
    _resourceCache[cacheKey] = resources;
    return resources;
  }

  static List<BuiltInSkill> _findNamedSkills(
    List<String> names,
    List<BuiltInSkill> catalog,
  ) {
    if (names.isEmpty || catalog.isEmpty) return const <BuiltInSkill>[];
    final wanted = names.map((e) => e.trim().toLowerCase()).toSet();
    final matches = catalog
        .where(
          (skill) => skill.matchNames.any(
            (name) => wanted.contains(name.trim().toLowerCase()),
          ),
        )
        .toList(growable: false);
    return List<BuiltInSkill>.unmodifiable(matches);
  }

  static List<BuiltInSkill> _findExplicitlyInvokedSkills(
    String text,
    List<BuiltInSkill> catalog,
  ) {
    if (text.trim().isEmpty) return const <BuiltInSkill>[];

    final invoked = <BuiltInSkill>[];
    for (final skill in catalog) {
      final matched = skill.matchNames.any((name) {
        final escapedName = RegExp.escape(name);
        final dollarPattern = RegExp(
          r'(^|[^A-Za-z0-9_-])\$' + escapedName + r'(?=$|[^A-Za-z0-9_-])',
          caseSensitive: false,
        );
        final slashPattern = RegExp(
          r'(^|\s)\/(?:skills?\s+)?' + escapedName + r'(?=$|\s)',
          caseSensitive: false,
        );
        return dollarPattern.hasMatch(text) || slashPattern.hasMatch(text);
      });
      if (matched) invoked.add(skill);
    }
    return List<BuiltInSkill>.unmodifiable(invoked);
  }

  static List<BuiltInSkill> _findImplicitlyMatchedSkills(
    String text,
    List<BuiltInSkill> catalog,
  ) {
    final normalized = _normalizeText(text);
    if (normalized.trim().isEmpty) return const <BuiltInSkill>[];

    final matches = <BuiltInSkill>[];
    for (final skill in catalog) {
      var score = 0;
      final nameParts = skill.matchNames
          .join(' ')
          .toLowerCase()
          .split(RegExp(r'[-_\s]+'))
          .where((e) => e.length > 2)
          .toList(growable: false);
      if (nameParts.isNotEmpty && nameParts.every(normalized.contains)) {
        score += 3;
      }
      for (final keyword in _keywordsFor(skill)) {
        if (normalized.contains(keyword)) score += 1;
      }
      if (score >= 3) matches.add(skill);
    }
    return List<BuiltInSkill>.unmodifiable(matches.take(2));
  }

  static List<BuiltInSkill> _dedupeSkills(List<BuiltInSkill> skills) {
    final seen = <String>{};
    final out = <BuiltInSkill>[];
    for (final skill in skills) {
      if (seen.add(skill.sourcePath)) out.add(skill);
    }
    return out;
  }

  static Iterable<String> _keywordsFor(BuiltInSkill skill) sync* {
    final stop = <String>{
      'with',
      'from',
      'that',
      'this',
      'into',
      'plus',
      'skill',
      'skills',
      'style',
      'agent',
      'agents',
      'directory',
      'resources',
    };
    final source = '${skill.matchNames.join(' ')} ${skill.description}'.toLowerCase();
    final seen = <String>{};
    for (final word in source.split(RegExp(r'[^a-z0-9]+'))) {
      if (word.length < 4 || stop.contains(word)) continue;
      if (seen.add(word)) yield word;
    }
  }

  static bool _looksSkillRelated(String text) {
    final normalized = _normalizeText(text);
    return normalized.contains('skill') || normalized.contains('技能');
  }

  static String _normalizeText(String text) {
    return text.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  static bool _shouldIncludeResource(String relativePath) {
    final normalized = relativePath.replaceAll('\\', '/');
    final parts = normalized.split('/');
    if (parts.any((e) => e.startsWith('.') || e == '__MACOSX')) return false;
    final top = parts.first.toLowerCase();
    final allowedTop = const <String>{
      'scripts',
      'references',
      'templates',
      'examples',
      'fixtures',
    };
    if (!allowedTop.contains(top) && parts.length > 1) return false;
    return _isTextResource(normalized);
  }

  static bool _isTextResource(String path) {
    final ext = p.extension(path).toLowerCase();
    return const <String>{
      '.md',
      '.txt',
      '.json',
      '.yaml',
      '.yml',
      '.sh',
      '.py',
      '.js',
      '.ts',
      '.dart',
      '.swift',
      '.m',
      '.h',
      '.html',
      '.css',
      '.xml',
      '.csv',
    }.contains(ext);
  }

  static String _nameFromSkillMarkdown(String markdown, String fallback) {
    final name = _frontMatterValue(markdown, 'name');
    final clean = name?.trim();
    if (clean != null && clean.isNotEmpty) return clean;
    return fallback;
  }

  static String _descriptionFromSkillMarkdown(String markdown) {
    final description = _frontMatterValue(markdown, 'description');
    if (description != null && description.trim().isNotEmpty) {
      return description.trim();
    }

    final lines = markdown.split('\n');
    var inFrontMatter = false;
    for (final raw in lines) {
      final line = raw.trim();
      if (line == '---') {
        inFrontMatter = !inFrontMatter;
        continue;
      }
      if (inFrontMatter || line.isEmpty || line.startsWith('#')) continue;
      return line.length <= 180 ? line : '${line.substring(0, 177)}...';
    }
    return '';
  }

  static String? _frontMatterValue(String markdown, String key) {
    final lines = markdown.split('\n');
    if (lines.isEmpty || lines.first.trim() != '---') return null;
    final wanted = key.toLowerCase();
    for (var i = 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line == '---') break;
      final separator = line.indexOf(':');
      if (separator <= 0) continue;
      final field = line.substring(0, separator).trim().toLowerCase();
      if (field != wanted) continue;
      return _unquoteYamlScalar(line.substring(separator + 1).trim());
    }
    return null;
  }

  static String _unquoteYamlScalar(String value) {
    if (value.length >= 2) {
      final first = value[0];
      final last = value[value.length - 1];
      if ((first == '"' && last == '"') || (first == "'" && last == "'")) {
        return value.substring(1, value.length - 1);
      }
    }
    return value;
  }

  static File? _findSkillFileInDirectory(Directory dir) {
    final upper = File(p.join(dir.path, 'SKILL.md'));
    if (upper.existsSync()) return upper;
    final lower = File(p.join(dir.path, 'skill.md'));
    if (lower.existsSync()) return lower;
    return null;
  }

  static String _sanitizeSkillName(String value) {
    final lower = value.trim().toLowerCase();
    final cleaned = lower
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'[^a-z0-9_-]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return cleaned;
  }

  static Future<void> _copyDirectory(Directory source, Directory target) async {
    if (!await target.exists()) await target.create(recursive: true);
    for (final entity in source.listSync(followLinks: false)) {
      final name = p.basename(entity.path);
      if (name == '.git' || name == '.DS_Store' || name == '__MACOSX') {
        continue;
      }
      final targetPath = p.join(target.path, name);
      if (entity is Directory) {
        await _copyDirectory(entity, Directory(targetPath));
      } else if (entity is File) {
        await entity.copy(targetPath);
      }
    }
  }
}
