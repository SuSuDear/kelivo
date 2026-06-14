import 'package:flutter/material.dart';

class DesktopMenuAnchor {
  static Offset? _position;
  static void setPosition(Offset position) => _position = position;
  static Offset positionOrCenter(BuildContext context) => _position ?? Offset.zero;
}
