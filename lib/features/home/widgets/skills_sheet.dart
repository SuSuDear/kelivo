import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../core/services/skills/builtin_skill_service.dart';

Future<String?> showSkillsSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const SkillsSheet(),
  );
}

class SkillsSheet extends StatefulWidget {
  const SkillsSheet({super.key});

  @override
  State<SkillsSheet> createState() => _SkillsSheetState();
}

class _SkillsSheetState extends State<SkillsSheet> {
  late Future<List<BuiltInSkill>> _future;

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
                  Icon(Icons.auto_awesome, color: cs.primary),
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
                    return const Center(child: Text('暂无技能'));
                  }
                  return ListView.separated(
                    controller: controller,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
                    itemCount: skills.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final skill = skills[index];
                      return Card(
                        elevation: 0,
                        color: cs.surfaceContainerHighest.withValues(alpha: 0.42),
                        child: ListTile(
                          title: Text(skill.name),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              skill.description.isEmpty
                                  ? '无描述'
                                  : skill.description,
                            ),
                          ),
                          leading: Icon(
                            skill.isBundled
                                ? Icons.verified_outlined
                                : Icons.folder_outlined,
                            color: cs.primary,
                          ),
                          trailing: Text(skill.isBundled ? '内置' : '用户'),
                          onTap: () {
                            Navigator.of(context).pop('\$${skill.name} ');
                          },
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
