import 'package:flutter/services.dart';

/// Codex-style bundled skill metadata.
class BuiltInSkill {
  const BuiltInSkill({
    required this.name,
    required this.assetPath,
    required this.description,
  });

  final String name;
  final String assetPath;
  final String description;
}

/// Loads app-bundled Codex-style skills from assets/skills/.system/*/SKILL.md.
///
/// This follows Codex's progressive disclosure model:
/// - the catalog exposes only name/description metadata;
/// - the full SKILL.md is injected only when the user explicitly invokes it
///   with `$skill-name`, `/skill-name`, `/skill skill-name`, or `/skills skill-name`.
class BuiltInSkillService {
  static const String _systemSkillsRoot = 'assets/skills/.system/';

  static List<BuiltInSkill>? _catalogCache;
  static final Map<String, String> _contentCache = <String, String>{};

  static Future<List<BuiltInSkill>> loadCatalog({AssetBundle? bundle}) async {
    if (bundle == null && _catalogCache != null) return _catalogCache!;

    final assetBundle = bundle ?? rootBundle;
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
        ),
      );
    }

    final readonly = List<BuiltInSkill>.unmodifiable(catalog);
    if (bundle == null) _catalogCache = readonly;
    return readonly;
  }

  static Future<String> buildPromptForUserMessage(
    String userMessage, {
    AssetBundle? bundle,
  }) async {
    final catalog = await loadCatalog(bundle: bundle);
    if (catalog.isEmpty) return '';

    final invoked = _findExplicitlyInvokedSkills(userMessage, catalog);
    final buffer = StringBuffer()
      ..writeln('## Built-in skills')
      ..writeln(
        'The app provides Codex-style built-in skills. A skill is a bundled directory with a SKILL.md file and optional resources. Use the catalog metadata below to decide whether a skill is relevant. Full SKILL.md instructions are provided only for explicitly invoked skills.',
      )
      ..writeln()
      ..writeln('Available built-in skills:');

    for (final skill in catalog) {
      final description = skill.description.isEmpty
          ? 'No description provided.'
          : skill.description;
      buffer.writeln('- ${skill.name}: $description');
    }

    if (invoked.isEmpty) {
      buffer
        ..writeln()
        ..writeln(
          'To load a skill, the user can explicitly invoke it with `$skill-name`, `/skill-name`, `/skill skill-name`, or `/skills skill-name`.',
        );
      return buffer.toString().trim();
    }

    buffer
      ..writeln()
      ..writeln('Loaded built-in skill instructions:');

    for (final skill in invoked) {
      final content = await _loadSkillContent(skill, bundle: bundle);
      if (content.trim().isEmpty) continue;
      buffer
        ..writeln('<skill name="${skill.name}" path="${skill.assetPath}">')
        ..writeln(content.trim())
        ..writeln('</skill>');
    }

    return buffer.toString().trim();
  }

  static Future<String> _loadSkillContent(
    BuiltInSkill skill, {
    AssetBundle? bundle,
  }) async {
    if (bundle == null && _contentCache.containsKey(skill.assetPath)) {
      return _contentCache[skill.assetPath]!;
    }

    final assetBundle = bundle ?? rootBundle;
    try {
      final content = await assetBundle.loadString(skill.assetPath, cache: true);
      if (bundle == null) _contentCache[skill.assetPath] = content;
      return content;
    } catch (_) {
      return '';
    }
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
}
