import 'package:flutter/material.dart';

/// Fill and foreground colors for highlighting a win.
({Color fill, Color onFill}) winColors(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? (fill: Colors.green.shade900, onFill: Colors.green.shade100)
    : (fill: Colors.green.shade100, onFill: Colors.green.shade900);
