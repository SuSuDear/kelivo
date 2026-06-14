import 'dart:async';

class DesktopSidebarTabBus {
  DesktopSidebarTabBus._();
  static final instance = DesktopSidebarTabBus._();
  final _controller = StreamController<int>.broadcast();
  Stream<int> get stream => _controller.stream;
  void setCurrentIndex(int index) {}
  void switchToAssistants() => _controller.add(0);
  void switchToTopics() => _controller.add(1);
}
