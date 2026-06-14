import 'dart:async';

enum ChatAction { newTopic, toggleLeftPanelTopics, toggleLeftPanelAssistants, focusInput, switchModel, enterGlobalSearch, exitGlobalSearch }
class ChatActionBus {
  ChatActionBus._();
  static final instance = ChatActionBus._();
  final _controller = StreamController<ChatAction>.broadcast();
  Stream<ChatAction> get stream => _controller.stream;
  void emit(ChatAction action) => _controller.add(action);
}
