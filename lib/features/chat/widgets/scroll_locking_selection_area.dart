import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoTheme;
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

/// iOS-style selection handles with a larger hit target for chat bubbles.
///
/// Visual design stays close to Cupertino, but the interactive area is expanded
/// so handle drags are less likely to miss and cancel the selection.
class _EnlargedCupertinoTextSelectionControls extends TextSelectionControls {
  // Flutter default radius is 6; enlarge slightly for chat list usability.
  static const double _handleRadius = 8.5;
  static const double _handleOverlap = 1.5;
  // Invisible padding around the painted handle (hit-test only).
  static const double _hitSlop = 14.0;

  Size _visualSize(double textLineHeight) {
    return Size(
      _handleRadius * 2,
      textLineHeight + _handleRadius * 2 - _handleOverlap,
    );
  }

  @override
  Size getHandleSize(double textLineHeight) {
    final visual = _visualSize(textLineHeight);
    return Size(
      visual.width + _hitSlop * 2,
      visual.height + _hitSlop * 2,
    );
  }

  @override
  Widget buildHandle(
    BuildContext context,
    TextSelectionHandleType type,
    double textLineHeight, [
    VoidCallback? onTap,
  ]) {
    final handleColor =
        CupertinoTheme.maybeOf(context)?.primaryColor ??
        Theme.of(context).colorScheme.primary;
    final visual = _visualSize(textLineHeight);

    final painted = CustomPaint(
      size: visual,
      painter: _EnlargedCupertinoHandlePainter(handleColor),
    );

    final Widget visualHandle = switch (type) {
      TextSelectionHandleType.left => painted,
      TextSelectionHandleType.right => Transform.rotate(
          angle: math.pi,
          child: painted,
        ),
      TextSelectionHandleType.collapsed => const SizedBox.shrink(),
    };

    // Expand hit target with transparent padding while keeping visual geometry.
    return Padding(
      padding: const EdgeInsets.all(_hitSlop),
      child: SizedBox(
        width: visual.width,
        height: visual.height,
        child: visualHandle,
      ),
    );
  }

  @override
  Offset getHandleAnchor(TextSelectionHandleType type, double textLineHeight) {
    final visual = _visualSize(textLineHeight);
    switch (type) {
      case TextSelectionHandleType.left:
        // Cupertino left anchor is bottom-center of the visual handle.
        return Offset(
          visual.width / 2 + _hitSlop,
          visual.height + _hitSlop,
        );
      case TextSelectionHandleType.right:
        return Offset(
          visual.width / 2 + _hitSlop,
          visual.height - 2 * _handleRadius + _handleOverlap + _hitSlop,
        );
      case TextSelectionHandleType.collapsed:
        final size = getHandleSize(textLineHeight);
        return Offset(size.width / 2, size.height / 2);
    }
  }

  @override
  Widget buildToolbar(
    BuildContext context,
    Rect globalEditableRegion,
    double textLineHeight,
    Offset selectionMidpoint,
    List<TextSelectionPoint> endpoints,
    TextSelectionDelegate delegate,
    ValueListenable<ClipboardStatus>? clipboardStatus,
    Offset? lastSecondaryTapDownPosition,
  ) {
    // Toolbar is provided via SelectionArea.contextMenuBuilder.
    return const SizedBox.shrink();
  }
}

class _EnlargedCupertinoHandlePainter extends CustomPainter {
  const _EnlargedCupertinoHandlePainter(this.color);

  final Color color;

  static const double _radius =
      _EnlargedCupertinoTextSelectionControls._handleRadius;
  static const double _overlap =
      _EnlargedCupertinoTextSelectionControls._handleOverlap;

  @override
  void paint(Canvas canvas, Size size) {
    const halfStrokeWidth = 1.25;
    final paint = Paint()..color = color;
    final circle = Rect.fromCircle(
      center: const Offset(_radius, _radius),
      radius: _radius,
    );
    final line = Rect.fromPoints(
      const Offset(_radius - halfStrokeWidth, 2 * _radius - _overlap),
      Offset(_radius + halfStrokeWidth, size.height),
    );
    final path = Path()
      ..addOval(circle)
      ..addRect(line);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _EnlargedCupertinoHandlePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

final TextSelectionControls _enlargedCupertinoTextSelectionControls =
    _EnlargedCupertinoTextSelectionControls();

/// Prefer enlarged Cupertino handles on Apple platforms.
/// Other platforms keep SelectionArea's built-in controls to avoid depending
/// on package-private selection-control symbols.
TextSelectionControls? chatSelectionControlsFor(TargetPlatform platform) {
  switch (platform) {
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
      return _enlargedCupertinoTextSelectionControls;
    case TargetPlatform.android:
    case TargetPlatform.fuchsia:
    case TargetPlatform.linux:
    case TargetPlatform.windows:
      return null;
  }
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
  bool _hasSelection = false;

  FocusNode get _focusNode => widget.focusNode ?? _internalFocusNode!;

  void _ensureInternalFocusNode() {
    if (widget.focusNode == null) {
      _internalFocusNode ??= FocusNode(debugLabel: 'chat-selection');
    }
  }

  void _syncLock() {
    // Keep the list locked for the whole selection session (focus or non-empty
    // selection) so re-grabbing a handle is less likely to start a scroll.
    final shouldLock = _hasSelection || _focusNode.hasFocus;
    if (_active == shouldLock) return;
    _active = shouldLock;
    _controller?.setActive(_owner, shouldLock);
  }

  void _handleFocusChange() {
    _syncLock();
  }

  @override
  void initState() {
    super.initState();
    _ensureInternalFocusNode();
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant ScrollLockingSelectionArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode?.removeListener(_handleFocusChange);
      if (widget.focusNode != null) {
        _internalFocusNode?.removeListener(_handleFocusChange);
        _internalFocusNode?.dispose();
        _internalFocusNode = null;
        widget.focusNode!.addListener(_handleFocusChange);
      } else {
        oldWidget.focusNode?.removeListener(_handleFocusChange);
        _ensureInternalFocusNode();
        _internalFocusNode!.addListener(_handleFocusChange);
      }
      _syncLock();
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
    _focusNode.removeListener(_handleFocusChange);
    if (_active) {
      _controller?.setActive(_owner, false);
      _active = false;
    }
    _internalFocusNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseTheme = Theme.of(context);
    final selectionTheme = baseTheme.textSelectionTheme.copyWith(
      selectionColor: baseTheme.colorScheme.primary.withValues(alpha: 0.28),
      selectionHandleColor: baseTheme.colorScheme.primary,
    );
    final selectionControls = widget.selectionControls ??
        chatSelectionControlsFor(baseTheme.platform);

    return Theme(
      data: baseTheme.copyWith(textSelectionTheme: selectionTheme),
      child: SelectionArea(
        focusNode: _focusNode,
        selectionControls: selectionControls,
        contextMenuBuilder: widget.contextMenuBuilder,
        magnifierConfiguration: widget.magnifierConfiguration,
        // Avoid naming SelectedContent explicitly: some Flutter SDK builds do
        // not surface that type name cleanly to app libraries even though the
        // SelectionArea callback itself is available.
        onSelectionChanged: (content) {
          final plainText = content?.plainText;
          _hasSelection =
              plainText is String && plainText.trim().isNotEmpty;
          _syncLock();
        },
        child: widget.child,
      ),
    );
  }
}
