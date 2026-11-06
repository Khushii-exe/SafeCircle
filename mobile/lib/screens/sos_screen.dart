import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../state.dart';
import '../theme.dart';
import '../widgets/glass.dart';
import '../widgets/sos_button.dart';

class SosScreen extends StatefulWidget {
  const SosScreen({super.key});
  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen> {
  bool sending = false;
  Map<String, dynamic>? result;
  String? failure;

  Future<void> _fire() async {
    if (sending) return;
    setState(() { sending = true; result = null; failure = null; });
    final s = context.read<AppState>();
    try {
      final r = await s.sendSos();
      if (mounted) setState(() => result = r);
    } catch (e) {
      if (mounted) setState(() => failure = e.toString());
    }
    if (mounted) setState(() => sending = false);
  }

  Future<void> _call112() => launchUrl(Uri(scheme: 'tel', path: '112'));

  Future<void> _textContact(AppState s) async {
    final t = s.trip;
    final p = s.me;
    if (t == null) return;
    final where = p == null ? 'location unknown' : 'https://maps.google.com/?q=${p.latitude},${p.longitude}';
    await launchUrl(Uri(scheme: 'sms', path: t['contact_phone'] as String, queryParameters: {'body': 'SafeCircle SOS: I need help. $where'}));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return SafeArea(
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 24, 16, 120), children: [
        const Center(child: Text('Send SOS', style: hTitle)),
        const SizedBox(height: 4),
        const Center(child: Text('Hold the button for 3 seconds', style: hSmall)),
        const SizedBox(height: 28),
        Center(child: SosButton(onFired: sending ? () {} : _fire, size: 220)),
        const SizedBox(height: 28),
        if (result != null)
          Glass(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('SOS received by our server', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(s.trip != null ? 'Your trusted contact was sent a message.' : 'No trip is active, so no contact was messaged.', style: hSmall),
              const SizedBox(height: 4),
              const Text('Delivery is not guaranteed. Also call 112.', style: hSmall),
            ]),
          ),
        if (failure != null)
          Glass(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(failure!, style: const TextStyle(color: C.red, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              const Text('The SOS did not reach our server. Use the options below.', style: hSmall),
            ]),
          ),
        const SizedBox(height: 12),
        PrimaryButton('Call 112', color: C.red, onPressed: _call112),
        if (s.trip != null) ...[const SizedBox(height: 8), GlassButton('Text my trusted contact', onPressed: () => _textContact(s))],
        const Padding(
          padding: EdgeInsets.only(top: 16),
          child: Text('Sends your location and time. In a later version it also attaches nearby-device records as unverified leads, never proof of involvement.', style: hSmall),
        ),
      ]),
    );
  }
}
