import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme.dart';

class GradientBackground extends StatelessWidget {
  const GradientBackground({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(gradient: C.gradient),
        child: SizedBox.expand(child: child),
      );
}

class Glass extends StatelessWidget {
  const Glass({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.radius = 24, this.margin});
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final EdgeInsets? margin;

  @override
  Widget build(BuildContext context) => Container(
        margin: margin,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              padding: padding,
              decoration: BoxDecoration(
                color: C.glass,
                borderRadius: BorderRadius.circular(radius),
                border: Border.all(color: C.glassBorder),
              ),
              child: child,
            ),
          ),
        ),
      );
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton(this.label, {super.key, this.onPressed, this.color = C.ink});
  final String label;
  final VoidCallback? onPressed;
  final Color color;
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 54,
        width: double.infinity,
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white, shape: const StadiumBorder(), textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          child: Text(label),
        ),
      );
}

class GlassButton extends StatelessWidget {
  const GlassButton(this.label, {super.key, this.onPressed});
  final String label;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 54,
        width: double.infinity,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(backgroundColor: C.glass, foregroundColor: C.ink, side: const BorderSide(color: C.ink, width: 1.5), shape: const StadiumBorder(), textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          child: Text(label),
        ),
      );
}

/// Pill toggle with a 48 dp touch target.
class Pill extends StatelessWidget {
  const Pill(this.label, {super.key, required this.selected, required this.onTap, this.dot});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? dot;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        label: label,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: selected ? C.ink : C.glass,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: selected ? C.ink : C.glassBorder),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (dot != null) ...[Container(width: 12, height: 12, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)), const SizedBox(width: 8)],
              Text(label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: selected ? Colors.white : C.ink)),
            ]),
          ),
        ),
      );
}

class GlassNav extends StatelessWidget {
  const GlassNav({super.key, required this.index, required this.onTap});
  final int index;
  final ValueChanged<int> onTap;
  static const items = [
    (Icons.map_outlined, 'Map'),
    (Icons.alt_route, 'Routes'),
    (Icons.verified_user_outlined, 'Trip'),
    (Icons.warning_amber_rounded, 'SOS'),
    (Icons.bluetooth_searching, 'Nearby'),
  ];
  @override
  Widget build(BuildContext context) => SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Glass(
          radius: 34,
          padding: const EdgeInsets.all(6),
          child: Row(children: [
            for (var i = 0; i < items.length; i++)
              Expanded(
                child: Semantics(
                  button: true,
                  selected: i == index,
                  label: items[i].$2,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(28),
                    onTap: () => onTap(i),
                    child: Container(
                      height: 56,
                      decoration: BoxDecoration(color: i == index ? const Color(0xCCFFFFFF) : Colors.transparent, borderRadius: BorderRadius.circular(28)),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(items[i].$1, color: C.ink),
                        Text(items[i].$2, style: TextStyle(fontSize: 12, fontWeight: i == index ? FontWeight.w800 : FontWeight.w600, color: i == index ? C.ink : C.body)),
                      ]),
                    ),
                  ),
                ),
              ),
          ]),
        ),
      );
}
