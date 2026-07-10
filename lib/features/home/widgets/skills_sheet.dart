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

  Future<void> _installSkill() async {
    final sourcePath = await _askInstallPath();
    if (sourcePath == null || sourcePath.trim().isEmpty) return;
    try {
      final skill = await BuiltInSkillService.installFromDirectory(sourcePath);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已安装技能：${skill.name}')),
      );
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('安装失败：$e')),
      );
    }
  }

  Future<String?> _askInstallPath() async {
    final controller = TextEditingController();
    final skillsDir = await BuiltInSkillService.userSkillsDirectory();
    if (!mounted) return null;
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('安装技能目录'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('请输入包含 SKILL.md 的本地目录路径：'),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: '/path/to/my-skill',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '安装位置：${skillsDir.path}',
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                  color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
              child: const Text('安装'),
            ),
          ],
        );
      },
    );
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
                    onPressed: _installSkill,
                    icon: const Icon(Icons.add),
                    label: const Text('安装'),
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
                            Navigator.of(context).pop('\$' + skill.name + ' ');
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
