import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

/// Coordinates temporary chat-list scroll locking while text selection is active.
///
/// Dragging selection handles inside a [ListView] often loses the gesture arena
/// to parent scrolling. While any registered selection is non-empty, the list
/// should refuse user scroll offsets without rebuilding the list tree.
class TextSelectionScrollLockController {
  final ValueNotifier<bool> locked = ValueNotifier<bool>(false);
  final Set<Object> _owners = <Object>{};

  void setActive(Object owner, bool active) {
    final wasLocked = _owners.isNotEmpty;
    if (active) {
      _owners.add(owner);
    } else {
      _owners.remove(owner);
    }
    final isLocked = _owners.isNotEmpty;
    if (wasLocked != isLocked) {
      locked.value = isLocked;
    }
  }

  void clear() {
    if (_owners.isEmpty) return;
    _owners.clear();
    locked.value = false;
  }

  void dispose() {
    locked.dispose();
    _owners.clear();
  }
}

/// Scroll physics that consults [lockedListenable] on every gesture sample.
///
/// Using a listenable (instead of swapping [NeverScrollableScrollPhysics] via
/// rebuild) avoids re-creating list children and wiping the active selection.
class SelectionLockScrollPhysics extends ScrollPhysics {
  const SelectionLockScrollPhysics({
    required this.lockedListenable,
    super.parent,
  });

  final ValueListenable<bool> lockedListenable;

  bool get _locked => lockedListenable.value;

  @override
  SelectionLockScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return SelectionLockScrollPhysics(
      lockedListenable: lockedListenable,
      parent: buildParent(ancestor),
    );
  }

  @override
  bool shouldAcceptUserOffset(ScrollMetrics position) {
    if (_locked) return false;
    return super.shouldAcceptUserOffset(position);
  }

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    if (_locked) return 0.0;
    return super.applyPhysicsToUserOffset(position, offset);
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    if (_locked) return null;
    return super.createBallisticSimulation(position, velocity);
  }

  @override
  bool get allowImplicitScrolling =>
      !_locked && super.allowImplicitScrolling;
}

class TextSelectionScrollLockScope extends InheritedWidget {
  const TextSelectionScrollLockScope({
    super.key,
    required this.controller,
    required super.child,
  });

  final TextSelectionScrollLockController controller;

  static TextSelectionScrollLockController? maybeOf(BuildContext context) {
    return context
        .getInheritedWidgetOfExactType<TextSelectionScrollLockScope>()
        ?.controller;
  }

  @override
  bool updateShouldNotify(TextSelectionScrollLockScope oldWidget) {
    return controller != oldWidget.controller;
  }
}

/// Lightweight toolbar used for chat body selection.
///
/// Uses AdaptiveTextSelectionToolbar.buttonItems for a simpler menu path while
/// still allowing the platform magnifier configuration.
Widget chatSelectionContextMenuBuilder(
  BuildContext context,
  SelectableRegionState selectableRegionState,
) {
  return AdaptiveTextSelectionToolbar.buttonItems(
    anchors: selectableRegionState.contextMenuAnchors,
    buttonItems: selectableRegionState.contextMenuButtonItems,
  );
}

/// [SelectionArea] that locks the surrounding chat list while a selection exists.
class ScrollLockingSelectionArea extends StatefulWidget {
  ScrollLockingSelectionArea({
    super.key,
    required this.child,
    this.focusNode,
    this.selectionControls,
    this.contextMenuBuilder = chatSelectionContextMenuBuilder,
    TextMagnifierConfiguration? magnifierConfiguration,
  }) : magnifierConfiguration = magnifierConfiguration ??
           TextMagnifier.adaptiveMagnifierConfiguration;

  final Widget child;
  final FocusNode? focusNode;
  final TextSelectionControls? selectionControls;
  final SelectableRegionContextMenuBuilder? contextMenuBuilder;
  final TextMagnifierConfiguration magnifierConfiguration;

  @override
  State<ScrollLockingSelectionArea> createState() =>
      _ScrollLockingSelectionAreaState();
}

class _ScrollLockingSelectionAreaState extends State<ScrollLockingSelectionArea> {
  final Object _owner = Object();
  FocusNode? _internalFocusNode;
  TextSelectionScrollLockController? _controller;
  bool _active = false;

  FocusNode get _focusNode => widget.focusNode ?? _internalFocusNode!;

  void _ensureInternalFocusNode() {
    if (widget.focusNode == null) {
      _internalFocusNode ??= FocusNode(debugLabel: 'chat-selection');
    }
  }

  void _setActive(bool active) {
    if (_active == active) return;
    _active = active;
    _controller?.setActive(_owner, active);
  }

  @override
  void initState() {
    super.initState();
    _ensureInternalFocusNode();
  }

  @override
  void didUpdateWidget(covariant ScrollLockingSelectionArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      if (widget.focusNode != null) {
        _internalFocusNode?.dispose();
        _internalFocusNode = null;
      } else {
        _ensureInternalFocusNode();
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = TextSelectionScrollLockScope.maybeOf(context);
    if (!identical(next, _controller)) {
      if (_active) {
        _controller?.setActive(_owner, false);
        next?.setActive(_owner, true);
      }
      _controller = next;
    }
  }

  @override
  void dispose() {
    if (_active) {
      _controller?.setActive(_owner, false);
      _active = false;
    }
    _internalFocusNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Keep selection highlight readable on chat surfaces.
    // Leave selectionControls null so SelectionArea picks the platform default
    // without depending on package-private handle-control symbols.
    // Magnifier uses Flutter's adaptive loupe (CupertinoTextMagnifier on iOS).
    final baseTheme = Theme.of(context);
    final selectionTheme = baseTheme.textSelectionTheme.copyWith(
      selectionColor: baseTheme.colorScheme.primary.withValues(alpha: 0.28),
      selectionHandleColor: baseTheme.colorScheme.primary,
    );

    return Theme(
      data: baseTheme.copyWith(textSelectionTheme: selectionTheme),
      child: SelectionArea(
        focusNode: _focusNode,
        selectionControls: widget.selectionControls,
        contextMenuBuilder: widget.contextMenuBuilder,
        magnifierConfiguration: widget.magnifierConfiguration,
        // Avoid naming SelectedContent explicitly: some Flutter SDK builds do
        // not surface that type name cleanly to app libraries even though the
        // SelectionArea callback itself is available.
        onSelectionChanged: (content) {
          final plainText = content?.plainText;
          final hasSelection =
              plainText is String && plainText.trim().isNotEmpty;
          _setActive(hasSelection);
        },
        child: widget.child,
      ),
    );
  }
}
