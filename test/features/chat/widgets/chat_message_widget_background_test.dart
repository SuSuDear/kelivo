import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/api/chat_api_service.dart';
import 'package:Kelivo/core/services/chat/chat_service.dart';
import 'package:Kelivo/features/chat/widgets/chat_message_widget.dart';
import 'package:Kelivo/features/home/controllers/stream_controller.dart'
    as home_stream;
import 'package:Kelivo/features/home/services/ask_user_interaction_service.dart';
import 'package:Kelivo/icons/lucide_adapter.dart';
import 'package:Kelivo/features/home/services/tool_approval_service.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/widgets/ios_tactile.dart';

SettingsProvider _createSettings(ChatMessageBackgroundStyle style) {
  final rawStyle = switch (style) {
    ChatMessageBackgroundStyle.frosted => 'frosted',
    ChatMessageBackgroundStyle.solid => 'solid',
    ChatMessageBackgroundStyle.defaultStyle => 'default',
  };
  SharedPreferences.setMockInitialValues({
    'display_chat_message_background_style_v1': rawStyle,
  });
  return SettingsProvider();
}

Widget _buildHarness({
  required SettingsProvider settings,
  required Widget child,
  AskUserInteractionService? askUserService,
  Locale? locale,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<SettingsProvider>.value(value: settings),
      ChangeNotifierProvider(create: (_) => ToolApprovalService()),
      ChangeNotifierProvider<AskUserInteractionService>.value(
        value: askUserService ?? AskUserInteractionService(),
      ),
    ],
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

Color _expectedNeutralStrong() =>
    ThemeData.light().colorScheme.onSurface.withValues(alpha: 0.78);

Finder _findNetworkImage(String url) {
  return find.byWidgetPredicate(
    (widget) =>
        widget is Image &&
        widget.image is NetworkImage &&
        (widget.image as NetworkImage).url == url,
  );
}

  testWidgets('tool message card uses blur in frosted mode', (tester) async {
      final settings = _createSettings(ChatMessageBackgroundStyle.frosted);

      await tester.pumpWidget(
        _buildHarness(
          settings: settings,
          child: ChatMessageWidget(
            message: ChatMessage(
              role: 'tool',
              content: jsonEncode({
                'tool': 'search_web',
                'arguments': {'query': 'Kelivo'},
                'result': '搜索结果',
              }),
              conversationId: 'conversation-3',
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(BackdropFilter), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('Web Search: Kelivo')).style?.color,
        _expectedNeutralStrong(),
      );
    });

    testWidgets('tool message card does not use blur in solid mode', (
      tester,
    ) async {
      final settings = _createSettings(ChatMessageBackgroundStyle.solid);

      await tester.pumpWidget(
        _buildHarness(
          settings: settings,
          child: ChatMessageWidget(
            message: ChatMessage(
              role: 'tool',
              content: jsonEncode({
                'tool': 'search_web',
                'arguments': {'query': 'Kelivo'},
                'result': '搜索结果',
              }),
              conversationId: 'conversation-4',
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(BackdropFilter), findsNothing);
      expect(
        tester.widget<Text>(find.text('Web Search: Kelivo')).style?.color,
        _expectedNeutralStrong(),
      );
    });

    testWidgets(
      'translation card uses blur and neutral header in frosted mode',
      (tester) async {
        final settings = _createSettings(ChatMessageBackgroundStyle.frosted);

        await tester.pumpWidget(
          _buildHarness(
            settings: settings,
            child: ChatMessageWidget(
              message: ChatMessage(
                role: 'assistant',
                content: 'Answer',
                translation: 'Translated answer',
                conversationId: 'conversation-5',
                isStreaming: true,
              ),
              showModelIcon: false,
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(BackdropFilter), findsNWidgets(2));
        expect(
          tester.widget<Text>(find.text('Translation')).style?.color,
          _expectedNeutralStrong(),
        );
      },
    );

    testWidgets('translation card removes blur in solid mode', (tester) async {
      final settings = _createSettings(ChatMessageBackgroundStyle.solid);

      await tester.pumpWidget(
        _buildHarness(
          settings: settings,
          child: ChatMessageWidget(
            message: ChatMessage(
              role: 'assistant',
              content: 'Answer',
              translation: 'Translated answer',
              conversationId: 'conversation-6',
              isStreaming: true,
            ),
            showModelIcon: false,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(BackdropFilter), findsNothing);
      expect(
        tester.widget<Text>(find.text('Translation')).style?.color,
        _expectedNeutralStrong(),
      );
    });

    testWidgets('local tool cards use local tool names and icons', (
      tester,
    ) async {
      final settings = _createSettings(ChatMessageBackgroundStyle.defaultStyle);

      await tester.pumpWidget(
        _buildHarness(
          settings: settings,
          child: ChatMessageWidget(
            message: ChatMessage(
              role: 'assistant',
              content: '',
              conversationId: 'conversation-local-tools',
              isStreaming: true,
            ),
            showModelIcon: false,
            reasoningSegments: const [
              ReasoningSegment(text: '需要本地信息', expanded: true, loading: false),
            ],
            toolParts: const [
              ToolUIPart(
                id: 'time-info',
                toolName: 'get_time_info',
                arguments: {},
                content: '{"date":"2026-05-06"}',
              ),
              ToolUIPart(
                id: 'clipboard-read',
                toolName: 'clipboard_tool',
                arguments: {'action': 'read'},
                content: '{"text":"hello"}',
              ),
              ToolUIPart(
                id: 'clipboard-write',
                toolName: 'clipboard_tool',
                arguments: {'action': 'write', 'text': 'hello'},
                content: '{"success":true,"text":"hello"}',
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Time Info'), findsOneWidget);
      expect(find.text('Read Clipboard'), findsOneWidget);
      expect(find.text('Write Clipboard'), findsOneWidget);
      expect(find.text('Speaking:'), findsOneWidget);
      expect(find.text('Replay this line'), findsOneWidget);
      expect(find.byTooltip('Replay'), findsOneWidget);
      final replayButton = tester.widget<IosIconButton>(
        find.descendant(
          of: find.byTooltip('Replay'),
          matching: find.byType(IosIconButton),
        ),
      );
      expect(replayButton.minSize, 30);
      expect(replayButton.padding, const EdgeInsets.all(6));
      expect(find.text('Clipboard'), findsNothing);
      expect(find.text('Tool Result: get_time_info'), findsNothing);
      expect(find.text('Tool Result: clipboard_tool'), findsNothing);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Icon && widget.icon == Lucide.clock,
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Icon && widget.icon == Lucide.ClipboardCheck,
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Icon && widget.icon == Lucide.ClipboardPen,
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Icon && widget.icon == Lucide.Volume2,
        ),
        findsOneWidget,
      );
    });

    testWidgets('two-line tool timeline keeps connector gap around icon', (
      tester,
    ) async {
      final settings = _createSettings(ChatMessageBackgroundStyle.defaultStyle);
      const query =
          'Kelivo Flutter chat message thinking tool timeline connector wraps';

      await tester.pumpWidget(
        _buildHarness(
          settings: settings,
          child: SizedBox(
            width: 320,
            child: ChatMessageWidget(
              message: ChatMessage(
                role: 'assistant',
                content: '',
                conversationId: 'conversation-tool-timeline-wrap',
                isStreaming: true,
              ),
              showModelIcon: false,
              reasoningSegments: const [
                ReasoningSegment(
                  text: '先确认问题',
                  expanded: false,
                  loading: false,
                  toolStartIndex: 0,
                ),
                ReasoningSegment(
                  text: '继续分析',
                  expanded: false,
                  loading: false,
                  toolStartIndex: 1,
                ),
              ],
              toolParts: const [
                ToolUIPart(
                  id: 'tool-wrap',
                  toolName: 'search_web',
                  arguments: {'query': query},
                  content: '搜索结果',
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final label = find.text('Web Search: $query');
      expect(label, findsOneWidget);
      expect(tester.getSize(label).height, greaterThan(20));

      final iconRect = tester.getRect(
        find.byWidgetPredicate(
          (widget) => widget is Icon && widget.icon == Lucide.Earth,
        ),
      );
      final topLineRect = tester.getRect(
        find.byKey(const ValueKey('chatMessageTimelineHeaderTopLine')).first,
      );
      final bottomLineRect = tester.getRect(
        find.byKey(const ValueKey('chatMessageTimelineHeaderBottomLine')).last,
      );

      final topGap = iconRect.top - topLineRect.bottom;
      final bottomGap = bottomLineRect.top - iconRect.bottom;
      expect(topGap, greaterThanOrEqualTo(3));
      expect(topGap, lessThanOrEqualTo(4));
      expect(bottomGap, greaterThanOrEqualTo(3));
      expect(bottomGap, lessThanOrEqualTo(4));
      expect(topGap, closeTo(bottomGap, 0.1));
      expect(topLineRect.height, closeTo(bottomLineRect.height, 0.1));
    });
