import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../core/services/skills/builtin_skill_service.dart';
import '../../../icons/lucide_adapter.dart';

enum SkillsSheetAction { useOnce, enableConversation, disableConversation }

class SkillsSheetResult {
  const SkillsSheetResult({required this.action, required this.skillName});

  final SkillsSheetAction action;
  final String skillName;
}

Future<SkillsSheetResult?> showSkillsSheet(
  BuildContext context, {
  List<String> activeSkillNames = const <String>[],
}) {
  return showModalBottomSheet<SkillsSheetResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => SkillsSheet(activeSkillNames: activeSkillNames),
  );
}

class SkillsSheet extends StatefulWidget {
  const SkillsSheet({super.key, this.activeSkillNames = const <String>[]});

  final List<String> activeSkillNames;

  @override
  State<SkillsSheet> createState() => _SkillsSheetState();
}

class _SkillsSheetState extends State<SkillsSheet> {
  late Future<List<BuiltInSkill>> _future;

  Set<String> get _activeSet => widget.activeSkillNames
      .map((e) => e.trim().toLowerCase())
      .where((e) => e.isNotEmpty)
      .toSet();

  @override
  void initState() {
    super.initState();
    _future = BuiltInSkillService.loadCatalog(refresh: true);
  }

  void _reload() {
    setState(() {
      _future = BuiltInSkillService.loadCatalog(refresh: true);
    });
  }

  Future<void> _importSkill() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: '选择 SKILL.md 或技能 zip',
      type: FileType.custom,
      allowedExtensions: const <String>['md', 'zip'],
      allowMultiple: false,
      withData: false,
    );
    final filePath = result?.files.single.path;
    if (filePath == null || filePath.trim().isEmpty) return;

    final lower = filePath.toLowerCase();
    if (lower.endsWith('.zip')) {
      await _installSkillZip(filePath);
      return;
    }
    await _installSkillFile(filePath);
  }

  Future<void> _installSkillFile(String filePath) async {
    try {
      final skill = await BuiltInSkillService.installFromSkillFile(filePath);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已导入技能：${skill.name}')),
      );
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入失败：$e')),
      );
    }
  }

  Future<void> _installSkillZip(String filePath) async {
    try {
      final skill = await BuiltInSkillService.installFromZipFile(filePath);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已导入技能包：${skill.name}')),
      );
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入失败：$e')),
      );
    }
  }

  String? _activeNameFor(BuiltInSkill skill) {
    for (final name in skill.matchNames) {
      if (_activeSet.contains(name.trim().toLowerCase())) return name;
    }
    return null;
  }

  Future<void> _showSkillActions(
    BuiltInSkill skill,
    bool active, {
    String? activeName,
  }) async {
    final result = await showModalBottomSheet<SkillsSheetResult>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(skill.name),
                subtitle: Text(
                  skill.description.isEmpty ? '无描述' : skill.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.play_arrow_outlined),
                title: const Text('本次使用'),
                onTap: () => Navigator.of(ctx).pop(
                  SkillsSheetResult(
                    action: SkillsSheetAction.useOnce,
                    skillName: skill.name,
                  ),
                ),
              ),
              ListTile(
                leading: Icon(
                  active ? Icons.remove_circle_outline : Icons.add_circle_outline,
                ),
                title: Text(active ? '关闭当前对话启用' : '当前对话启用'),
                onTap: () => Navigator.of(ctx).pop(
                  SkillsSheetResult(
                    action: active
                        ? SkillsSheetAction.disableConversation
                        : SkillsSheetAction.enableConversation,
                    skillName: active ? (activeName ?? skill.name) : skill.name,
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (!mounted || result == null) return;
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.62,
      minChildSize: 0.45,
      maxChildSize: 0.9,
      builder: (ctx, controller) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 8),
              child: Row(
                children: [
                  Icon(Lucide.Astroid, color: cs.primary),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Skills',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _importSkill,
                    icon: const Icon(Icons.file_upload_outlined),
                    label: const Text('导入'),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(ctx).maybePop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
            Expanded(
              child: FutureBuilder<List<BuiltInSkill>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final skills = snapshot.data ?? const <BuiltInSkill>[];
                  if (skills.isEmpty) {
                    return const Center(child: Text('暂无技能，点击“导入”添加 SKILL.md 或 zip'));
                  }
                  return ListView.separated(
                    controller: controller,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
                    itemCount: skills.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 4),
                    itemBuilder: (context, index) {
                      final skill = skills[index];
                      final activeName = _activeNameFor(skill);
                      final active = activeName != null;
                      return Card(
                        margin: EdgeInsets.zero,
                        elevation: 0,
                        color: active
                            ? cs.primaryContainer.withValues(alpha: 0.55)
                            : cs.surfaceContainerHighest.withValues(alpha: 0.42),
                        child: ListTile(
                          dense: true,
                          visualDensity: const VisualDensity(vertical: -3),
                          minVerticalPadding: 6,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 2,
                          ),
                          title: Text(
                            skill.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              skill.description.isEmpty ? '无描述' : skill.description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          leading: Icon(
                            active ? Icons.check_circle_outline : Icons.folder_outlined,
                            size: 20,
                            color: active ? cs.primary : cs.onSurfaceVariant,
                          ),
                          trailing: active ? const Text('当前对话') : null,
                          onTap: () => _showSkillActions(
                            skill,
                            active,
                            activeName: activeName,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
