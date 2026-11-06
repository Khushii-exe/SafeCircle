import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets/glass.dart';
import '../widgets/sos_button.dart';

class TripScreen extends StatefulWidget {
  const TripScreen({super.key});
  @override
  State<TripScreen> createState() => _TripScreenState();
}

class _TripScreenState extends State<TripScreen> with TickerProviderStateMixin {
  final name = TextEditingController();
  final phone = TextEditingController();
  int minutes = 20;
  int interval = 300;
  Timer? _tick;
  String? err;
  bool _extending = false;
  int _extendCount = 0;

  // Pulse animation for timer when < 30 s
  late final AnimationController _pulse;

  // Grace-period modal tracking
  bool _graceShowing = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
        _checkExpiry();
      }
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _pulse.dispose();
    name.dispose();
    phone.dispose();
    super.dispose();
  }

  /// Fires the grace-period modal exactly once when the timer crosses 0.
  void _checkExpiry() {
    final s = context.read<AppState>();
    final t = s.trip;
    if (t == null) {
      if (_pulse.isAnimating) _pulse.stop();
      return;
    }
    final deadline = parseUtc(t['next_deadline'] as String);
    final remaining = deadline.difference(DateTime.now().toUtc());
    final shouldPulse = !remaining.isNegative && remaining.inSeconds <= 30;
    if (shouldPulse && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!shouldPulse && _pulse.isAnimating) {
      _pulse.stop();
    }
    if (_graceShowing) return;
    if (DateTime.now().toUtc().isAfter(deadline)) {
      _graceShowing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _showGraceModal(s));
    }
  }

  void _showGraceModal(AppState s) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _GraceModal(
        onSafe: () async {
          Navigator.of(context).pop();
          _graceShowing = false;
          await _run(() => s.imSafe());
        },
        onSos: () {
          Navigator.of(context).pop();
          _graceShowing = false;
          context.read<AppState>().setTab(3); // navigate to SOS tab
        },
        onGraceExpired: () {
          if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
          _graceShowing = false;
          context.read<AppState>().setTab(3);
        },
      ),
    );
  }

  String _countdown(DateTime deadline) {
    final d = deadline.difference(DateTime.now().toUtc());
    if (d.isNegative) return '00:00';
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  /// Returns the colour for the timer based on remaining seconds.
  Color _timerColor(Duration remaining) {
    if (remaining.inSeconds <= 30) return C.red;
    if (remaining.inSeconds <= 120) return C.amber;
    return C.ink;
  }

  Future<void> _run(Future<void> Function() f) async {
    try {
      await f();
      if (mounted) setState(() => err = null);
    } on ApiException catch (e) {
      if (mounted) setState(() => err = e.message);
    }
  }

  Future<void> _extend(AppState s) async {
    if (_extending) return;
    setState(() => _extending = true);
    try {
      await s.imSafe(extendSeconds: 600);
      _extendCount++;
      if (mounted) {
        setState(() { err = null; _extending = false; });
        // Show banner with the new check-in time
        final t = s.trip;
        if (t != null) {
          final deadline = parseUtc(t['next_deadline'] as String);
          final hhmm = '${deadline.toLocal().hour.toString().padLeft(2,'0')}:${deadline.toLocal().minute.toString().padLeft(2,'0')}';
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Check-in extended by 10 min. Next check-in at $hhmm.'),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ));
        }
      }
    } on ApiException catch (e) {
      if (mounted) setState(() { err = e.message; _extending = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final t = s.trip;
    return SafeArea(
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 20, 16, 120), children: [
        const Text('Guarded trip', style: hTitle),
        const SizedBox(height: 12),
        if (t == null) ..._form(s) else ..._active(s, t),
        if (err != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(err!, style: const TextStyle(color: C.red, fontWeight: FontWeight.w600))),
      ]),
    );
  }

  List<Widget> _form(AppState s) {
    final sel = s.selectedRoute;
    return [
      if (sel != null)
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: C.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: C.accent.withValues(alpha: 0.3)),
          ),
          child: Row(children: [
            const Icon(Icons.route, color: C.accent, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Guarding: ${sel['name']} (${(sel['minutes'] as num).round()} min, ${(sel['km'] as num).toStringAsFixed(1)} km)',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: C.ink),
              ),
            ),
          ]),
        ),
      const Text('Pick someone you trust. If you miss a check-in and do not answer, our server alerts them with your last known location.', style: hSmall),
      const SizedBox(height: 16),
      _field(name, 'Trusted contact name'),
      const SizedBox(height: 12),
      _field(phone, 'Contact phone number', keyboard: TextInputType.phone),
      const SizedBox(height: 16),
      Glass(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Expected trip time: $minutes min', style: const TextStyle(fontWeight: FontWeight.w700)),
          Slider(value: minutes.toDouble(), min: 5, max: 120, divisions: 23, label: '$minutes min', onChanged: (v) => setState(() => minutes = v.round())),
          Text('Check in every ${interval ~/ 60} min', style: const TextStyle(fontWeight: FontWeight.w700)),
          Slider(value: interval / 60, min: 1, max: 15, divisions: 14, label: '${interval ~/ 60} min', onChanged: (v) => setState(() => interval = v.round() * 60)),
        ]),
      ),
      const SizedBox(height: 16),
      PrimaryButton('Start trip', onPressed: () {
        if (name.text.trim().isEmpty || phone.text.trim().length < 6) {
          setState(() => err = 'Enter your contact\'s name and phone number.');
          return;
        }
        _run(() => s.startTrip(name.text.trim(), phone.text.trim(), minutes, interval));
      }),
      const Padding(padding: EdgeInsets.only(top: 12), child: Text('Location sharing is visible and consent-based. Alerts need a connection or SMS fallback; no app can guarantee delivery.', style: hSmall)),
    ];
  }

  List<Widget> _active(AppState s, Map<String, dynamic> t) {
    final status = t['status'] as String;
    final deadline = parseUtc(t['next_deadline'] as String);
    final remaining = deadline.difference(DateTime.now().toUtc());
    final escalated = status == 'escalated';
    final prompted = status == 'prompted';
    final timerColor = escalated || prompted ? C.red : _timerColor(remaining);
    final shouldPulse = !remaining.isNegative && remaining.inSeconds <= 30;

    return [
      Text('Sharing live location with ${t['contact_name']}', style: hSmall),
      const SizedBox(height: 12),
      // ── Dynamic timer card ──
      AnimatedBuilder(
        animation: _pulse,
        builder: (_, __) {
          final scale = shouldPulse ? (1.0 + _pulse.value * 0.025) : 1.0;
          return Transform.scale(
            scale: scale,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: timerColor.withValues(alpha: shouldPulse ? 0.10 + _pulse.value * 0.06 : 0.07),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: timerColor.withValues(alpha: 0.35), width: 1.5),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  escalated ? 'Your contact has been alerted' : prompted ? 'Are you OK? Confirm now' : 'Next check-in in',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: timerColor),
                ),
                Text(
                  _countdown(deadline),
                  style: TextStyle(fontSize: 44, fontWeight: FontWeight.w800, height: 1.1, color: timerColor),
                ),
                if (_extendCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Extended $_extendCount time${_extendCount == 1 ? '' : 's'}', style: TextStyle(fontSize: 12, color: timerColor.withValues(alpha: 0.7))),
                  ),
              ]),
            ),
          );
        },
      ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: PrimaryButton("I'm safe", onPressed: () => _run(() => s.imSafe()))),
        const SizedBox(width: 8),
        Expanded(
          child: GlassButton(
            _extending ? 'Extending…' : 'Extend 10 min',
            onPressed: _extending ? null : () => _extend(s),
          ),
        ),
      ]),
      const SizedBox(height: 8),
      GlassButton('End trip', onPressed: () => _run(s.endTrip)),
      const Padding(
        padding: EdgeInsets.only(top: 12),
        child: Text('If a check-in is missed, our server asks you first, then alerts your trusted contact. The app cannot lock your power button or force GPS on; turning location off will look like a missed check-in.', style: hSmall),
      ),
    ];
  }

  Widget _field(TextEditingController c, String label, {TextInputType? keyboard}) => TextField(
        controller: c,
        keyboardType: keyboard,
        decoration: InputDecoration(labelText: label, filled: true, fillColor: C.glass, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16))),
      );
}

// ──────────────────────────────────────────────
// Grace-period modal — shown when timer hits 0
// ──────────────────────────────────────────────
class _GraceModal extends StatefulWidget {
  const _GraceModal({required this.onSafe, required this.onSos, required this.onGraceExpired});
  final VoidCallback onSafe;
  final VoidCallback onSos;
  final VoidCallback onGraceExpired;
  @override
  State<_GraceModal> createState() => _GraceModalState();
}

class _GraceModalState extends State<_GraceModal> {
  static const _graceSeconds = 60;
  int _remaining = _graceSeconds;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _remaining--);
      if (_remaining <= 0) {
        _t?.cancel();
        widget.onGraceExpired();
      }
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Color get _bg => _remaining <= 10 ? C.red : (_remaining <= 30 ? C.amber : C.accent);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Grace countdown ring
          SizedBox(
            width: 100,
            height: 100,
            child: Stack(alignment: Alignment.center, children: [
              CircularProgressIndicator(
                value: _remaining / _graceSeconds,
                strokeWidth: 8,
                color: _bg,
                backgroundColor: _bg.withValues(alpha: 0.15),
              ),
              Text(
                '$_remaining',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: _bg),
              ),
            ]),
          ),
          const SizedBox(height: 20),
          const Text('Are you safe?', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(
            'Your check-in time has passed. Respond within $_remaining seconds or your contact will be alerted.',
            textAlign: TextAlign.center,
            style: hSmall,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: FilledButton(
              onPressed: widget.onSafe,
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1B8A44), foregroundColor: Colors.white, shape: const StadiumBorder()),
              child: const Text("I'm Safe", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 10),
          // Compact SOS hold-button
          Center(child: SosButton(onFired: widget.onSos, size: 120)),
          const SizedBox(height: 8),
          const Text('Hold the SOS button for 3 s to alert your contact now', style: hSmall, textAlign: TextAlign.center),
        ]),
      ),
    );
  }
}
