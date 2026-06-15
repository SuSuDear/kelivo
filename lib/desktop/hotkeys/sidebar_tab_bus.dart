import 'dart:async';

class DesktopSidebarTabBus {
  DesktopSidebarTabBus._();
  static final DesktopSidebarTabBus instance = DesktopSidebarTabBus._();
  final _controller = StreamController<int>.broadcast();
  Stream<int> get stream => _controller.stream;
  int _currentIndex = 0;
  int get currentIndex => _currentIndex;
  void setCurrentIndex(int index) => _currentIndex = index;
  void switchToAssistants() => _controller.add(0);
  void switchToTopics() => _controller.add(1);
}
