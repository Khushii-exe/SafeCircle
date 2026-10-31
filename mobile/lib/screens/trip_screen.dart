import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets/glass.dart';

class TripScreen extends StatefulWidget {
  const TripScreen({super.key});
  @override
  State<TripScreen> createState() => _TripScreenState();
}

class _TripScreenState extends State<TripScreen> {
  final name = TextEditingController();
  final phone = TextEditingController();
  int minutes = 20;
  int interval = 300;
  Timer? _tick;
  String? err;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    name.dispose();
    phone.dispose();
    super.dispose();
  }

  String _countdown(DateTime deadline) {
    final d = deadline.difference(DateTime.now().toUtc());
    if (d.isNegative) return '00:00';
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _run(Future<void> Function() f) async {
    try {
      await f();
      if (mounted) setState(() => err = null);
    } on ApiException catch (e) {
      if (mounted) setState(() => err = e.message);
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
    final prompted = status == 'prompted';
    final escalated = status == 'escalated';
    return [
      Text('Sharing live location with ${t['contact_name']}', style: hSmall),
      const SizedBox(height: 12),
      Glass(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(escalated ? 'Your contact has been alerted' : prompted ? 'Are you OK? Confirm now' : 'Next check-in in', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: escalated || prompted ? C.red : C.body)),
          Text(_countdown(deadline), style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w800, height: 1.1)),
        ]),
      ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: PrimaryButton("I'm safe", onPressed: () => _run(() => s.imSafe()))),
        const SizedBox(width: 8),
        Expanded(child: GlassButton('Extend 10 min', onPressed: () => _run(() => s.imSafe(extendSeconds: 600)))),
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
