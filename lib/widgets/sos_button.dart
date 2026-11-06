import 'package:flutter/material.dart';

import '../theme.dart';

/// Hold-to-send SOS button with animated progress ring.
/// Used on the SOS screen and in the trip expiry grace-period modal.
class SosButton extends StatefulWidget {
  const SosButton({super.key, required this.onFired, this.size = 180.0});
  final VoidCallback onFired;
  final double size;
  @override
  State<SosButton> createState() => _SosButtonState();
}

class _SosButtonState extends State<SosButton> with SingleTickerProviderStateMixin {
  late final AnimationController _hold;

  @override
  void initState() {
    super.initState();
    _hold = AnimationController(vsync: this, duration: const Duration(seconds: 3))
      ..addStatusListener((st) {
        if (st == AnimationStatus.completed) widget.onFired();
      });
  }

  @override
  void dispose() {
    _hold.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sz = widget.size;
    final inner = sz - 32;
    return Semantics(
      button: true,
      label: 'SOS. Press and hold for three seconds to send',
      onLongPress: widget.onFired,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => _hold.forward(from: 0),
        onPointerUp: (_) {
          if (_hold.status != AnimationStatus.completed) _hold.reset();
        },
        onPointerCancel: (_) => _hold.reset(),
        child: AnimatedBuilder(
          animation: _hold,
          builder: (_, __) => SizedBox(
            width: sz,
            height: sz,
            child: Stack(alignment: Alignment.center, children: [
              SizedBox(
                width: sz,
                height: sz,
                child: CircularProgressIndicator(
                  value: _hold.value,
                  strokeWidth: 10,
                  color: C.red,
                  backgroundColor: const Color(0xB3FFFFFF),
                ),
              ),
              Container(
                width: inner,
                height: inner,
                decoration: BoxDecoration(
                  color: C.red,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: C.red.withValues(alpha: 0.25), blurRadius: 0, spreadRadius: 10)],
                ),
                alignment: Alignment.center,
                child: const Text('SOS', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

