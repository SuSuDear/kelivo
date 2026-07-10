import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../../utils/app_directories.dart';

/// Codex-style skill metadata.
class BuiltInSkill {
  const BuiltInSkill({
    required this.name,
    required this.description,
    required this.isBundled,
    this.assetPath,
    this.directoryPath,
  });

  final String name;
  final String description;
  final bool isBundled;
  final String? assetPath;
  final String? directoryPath;

  bool get isUserInstalled => !isBundled;

  String get sourcePath => assetPath ?? directoryPath ?? name;
}

/// Loads app-bundled and user-installed Codex-style skills.
///
/// This follows Codex's progressive disclosure model:
/// - the catalog exposes only name/description metadata;
/// - the full SKILL.md and small text resources are injected only when the user
///   explicitly invokes a skill or when a high-confidence description match is
///   found for the current task.
class BuiltInSkillService {
  static const String _systemSkillsRoot = 'assets/skills/.system/';
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
    if (bundle == null && !refresh && _catalogCache != null) {
      return _catalogCache!;
    }

    final assetBundle = bundle ?? rootBundle;
    final catalog = <BuiltInSkill>[
      ...await _loadBundledCatalog(assetBundle),
      ...await _loadUserCatalog(),
    ];
    catalog.sort((a, b) {
      if (a.isBundled != b.isBundled) return a.isBundled ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    final readonly = List<BuiltInSkill>.unmodifiable(catalog);
    if (bundle == null) _catalogCache = readonly;
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
    return BuiltInSkill(
      name: p.basename(target.path),
      description: _descriptionFromSkillMarkdown(content),
      directoryPath: target.path,
      isBundled: false,
    );
  }

  static Future<String> buildPromptForUserMessage(
    String userMessage, {
    AssetBundle? bundle,
  }) async {
    final catalog = await loadCatalog(bundle: bundle);
    if (catalog.isEmpty) return '';
    final installDir = await userSkillsDirectory();

    final explicit = _findExplicitlyInvokedSkills(userMessage, catalog);
    final implicit = explicit.isEmpty
        ? _findImplicitlyMatchedSkills(userMessage, catalog)
        : const <BuiltInSkill>[];
    final loaded = _dedupeSkills(<BuiltInSkill>[...explicit, ...implicit]);

    final buffer = StringBuffer()
      ..writeln('## Built-in skills')
      ..writeln(
        'The app provides Codex-style skills. A skill is a bundled or user-installed directory with a SKILL.md file plus optional resources such as scripts, references, templates, examples, or fixtures. Use the catalog metadata below to decide whether a skill is relevant. Full SKILL.md instructions are loaded only when explicitly invoked or implicitly matched with high confidence.',
      )
      ..writeln('User-installed skills directory: ${installDir.path}')
      ..writeln(
        'Manual install rule: copy each skill directory that contains SKILL.md into the user-installed skills directory above. The app discovers immediate subdirectories as installed skills.',
      )
      ..writeln()
      ..writeln('Available skills:');

    for (final skill in catalog) {
      final description = skill.description.isEmpty
          ? 'No description provided.'
          : skill.description;
      final source = skill.isBundled ? 'built-in' : 'user-installed';
      buffer.writeln('- ${skill.name} [$source]: $description');
    }

    if (loaded.isEmpty) {
      buffer
        ..writeln()
        ..writeln(
          'To load a skill, the user can explicitly invoke it with `\$skill-name`, `/skill-name`, `/skill skill-name`, or `/skills skill-name`. The `/skills` command opens the skill selector UI.',
        );
      return buffer.toString().trim();
    }

    buffer
      ..writeln()
      ..writeln('Loaded skill instructions:');

    for (final skill in loaded) {
      final trigger = explicit.contains(skill) ? 'explicit' : 'implicit';
      final content = await _loadSkillContent(skill, bundle: bundle);
      final resources = await _loadSkillResources(skill, bundle: bundle);
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

  static Future<List<BuiltInSkill>> _loadBundledCatalog(
    AssetBundle assetBundle,
  ) async {
    final List<String> assets;
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(assetBundle);
      assets = manifest.listAssets();
    } catch (_) {
      return const <BuiltInSkill>[];
    }

    final skillPaths = assets
        .where((path) =>
            path.startsWith(_systemSkillsRoot) && path.endsWith('/SKILL.md'))
        .toList(growable: false)
      ..sort();

    final catalog = <BuiltInSkill>[];
    for (final path in skillPaths) {
      final name = _skillNameFromPath(path);
      if (name.isEmpty) continue;

      String content = '';
      try {
        content = await assetBundle.loadString(path, cache: true);
      } catch (_) {}

      catalog.add(
        BuiltInSkill(
          name: name,
          assetPath: path,
          description: _descriptionFromSkillMarkdown(content),
          isBundled: true,
        ),
      );
    }
    return catalog;
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
        catalog.add(
          BuiltInSkill(
            name: p.basename(entity.path),
            description: _descriptionFromSkillMarkdown(content),
            directoryPath: entity.path,
            isBundled: false,
          ),
        );
      }
      return catalog;
    } catch (_) {
      return const <BuiltInSkill>[];
    }
  }

  static Future<String> _loadSkillContent(
    BuiltInSkill skill, {
    AssetBundle? bundle,
  }) async {
    final cacheKey = 'content:${skill.sourcePath}';
    if (bundle == null && _contentCache.containsKey(cacheKey)) {
      return _contentCache[cacheKey]!;
    }

    var content = '';
    if (skill.assetPath != null) {
      try {
        content = await (bundle ?? rootBundle).loadString(
          skill.assetPath!,
          cache: true,
        );
      } catch (_) {}
    } else if (skill.directoryPath != null) {
      final skillFile = _findSkillFileInDirectory(Directory(skill.directoryPath!));
      if (skillFile != null) {
        try {
          content = await skillFile.readAsString();
        } catch (_) {}
      }
    }

    if (content.length > _maxSkillContentChars) {
      content = '${content.substring(0, _maxSkillContentChars)}\n\n[SKILL.md truncated]';
    }
    if (bundle == null) _contentCache[cacheKey] = content;
    return content;
  }

  static Future<String> _loadSkillResources(
    BuiltInSkill skill, {
    AssetBundle? bundle,
  }) async {
    final cacheKey = 'resources:${skill.sourcePath}';
    if (bundle == null && _resourceCache.containsKey(cacheKey)) {
      return _resourceCache[cacheKey]!;
    }

    final resources = skill.assetPath != null
        ? await _loadAssetResources(skill, bundle: bundle)
        : await _loadFileResources(skill);
    if (bundle == null) _resourceCache[cacheKey] = resources;
    return resources;
  }

  static Future<String> _loadAssetResources(
    BuiltInSkill skill, {
    AssetBundle? bundle,
  }) async {
    final assetPath = skill.assetPath;
    if (assetPath == null) return '';
    final root = assetPath.substring(0, assetPath.lastIndexOf('/') + 1);
    final assetBundle = bundle ?? rootBundle;

    final List<String> assets;
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(assetBundle);
      assets = manifest.listAssets();
    } catch (_) {
      return '';
    }

    var total = 0;
    var count = 0;
    final buffer = StringBuffer();
    for (final path in assets.where((e) => e.startsWith(root)).toList()..sort()) {
      final rel = path.substring(root.length);
      if (rel == 'SKILL.md' || !_shouldIncludeResource(rel)) continue;
      if (count >= _maxResourceFiles || total >= _maxTotalResourceBytes) break;
      try {
        final content = await assetBundle.loadString(path, cache: true);
        if (content.length > _maxResourceBytes) continue;
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
    return buffer.toString().trim();
  }

  static Future<String> _loadFileResources(BuiltInSkill skill) async {
    final directoryPath = skill.directoryPath;
    if (directoryPath == null) return '';
    final dir = Directory(directoryPath);
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
    return buffer.toString().trim();
  }

  static List<BuiltInSkill> _findExplicitlyInvokedSkills(
    String text,
    List<BuiltInSkill> catalog,
  ) {
    if (text.trim().isEmpty) return const <BuiltInSkill>[];

    final invoked = <BuiltInSkill>[];
    for (final skill in catalog) {
      final escapedName = RegExp.escape(skill.name);
      final dollarPattern = RegExp(
        r'(^|[^A-Za-z0-9_-])\$' + escapedName + r'(?=$|[^A-Za-z0-9_-])',
        caseSensitive: false,
      );
      final slashPattern = RegExp(
        r'(^|\s)/(?:skills?\s+)?' + escapedName + r'(?=$|\s)',
        caseSensitive: false,
      );
      if (dollarPattern.hasMatch(text) || slashPattern.hasMatch(text)) {
        invoked.add(skill);
      }
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
      final nameParts = skill.name
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
      if (skill.name == 'skill-creator' &&
          _containsAny(normalized, const <String>[
            'create skill',
            'build skill',
            'write skill',
            'new skill',
            '创建技能',
            '新建技能',
            '制作技能',
            '写一个技能',
          ])) {
        score += 4;
      }
      if (skill.name == 'skill-installer' &&
          _containsAny(normalized, const <String>[
            'install skill',
            'import skill',
            'add skill',
            '安装技能',
            '导入技能',
            '添加技能',
          ])) {
        score += 4;
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
    final source = '${skill.name} ${skill.description}'.toLowerCase();
    final seen = <String>{};
    for (final word in source.split(RegExp(r'[^a-z0-9]+'))) {
      if (word.length < 4 || stop.contains(word)) continue;
      if (seen.add(word)) yield word;
    }
  }

  static bool _containsAny(String text, List<String> needles) {
    for (final needle in needles) {
      if (text.contains(needle)) return true;
    }
    return false;
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

  static String _skillNameFromPath(String path) {
    final parts = path.split('/');
    if (parts.length < 2) return '';
    return parts[parts.length - 2].trim();
  }

  static String _descriptionFromSkillMarkdown(String markdown) {
    final lines = markdown.split('\n');
    var inFrontMatter = false;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (i == 0 && line == '---') {
        inFrontMatter = true;
        continue;
      }
      if (inFrontMatter) {
        if (line == '---') break;
        if (line.toLowerCase().startsWith('description:')) {
          return line.substring('description:'.length).trim().replaceAll('"', '');
        }
      }
    }

    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#') || line == '---') continue;
      return line.length <= 180 ? line : '${line.substring(0, 177)}...';
    }
    return '';
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
