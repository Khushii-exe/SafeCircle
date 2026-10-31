import 'package:flutter/material.dart';

class C {
  static const ink = Color(0xFF1F1B55); // text, primary buttons
  static const body = Color(0xFF2A3F6E); // secondary text
  static const accent = Color(0xFF2E73B0);
  static const navy = Color(0xFF243F7F); // weak-signal layer
  static const amber = Color(0xFFF5A83D); // amber concern
  static const red = Color(0xFFC62828); // reviewed red concern, SOS
  static const glass = Color(0x8CFFFFFF);
  static const glassBorder = Color(0xD9FFFFFF);
  static const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFE3F4FA), Color(0xFFB0DCEB), Color(0xFF8FD0E8), Color(0xFF6EC0DC)],
    stops: [0, 0.35, 0.7, 1],
  );
}

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: C.accent, primary: C.ink, brightness: Brightness.light),
  );
  return base.copyWith(
    scaffoldBackgroundColor: Colors.transparent,
    textTheme: base.textTheme.apply(bodyColor: C.ink, displayColor: C.ink),
  );
}

const hSmall = TextStyle(fontSize: 13, height: 1.4, color: C.body);
const hTitle = TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: C.ink);
