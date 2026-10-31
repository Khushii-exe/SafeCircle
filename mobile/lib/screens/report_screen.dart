import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets/glass.dart';

const _cats = {
  'poor_lighting': 'Poor lighting',
  'isolated': 'Isolated',
  'harassment': 'Harassment',
  'no_people': 'No people around',
  'blocked_path': 'Blocked path',
  'other': 'Other',
};

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});
  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  String cat = 'poor_lighting';
  String when = 'night';
  final note = TextEditingController();
  bool sending = false;

  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final s = context.read<AppState>();
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => sending = true);
    try {
      final r = await s.submitReport(cat, when, note.text.trim());
      String msg = r['counted'] == true ? 'Report added.' : 'You already reported this here in the last 24 hours, so it counts once.';
      if (r['pending_review'] == true) msg += ' This place now needs moderator review.';
      if (r['verified_presence'] != true) msg += ' Location not confirmed, so it counts for less.';
      messenger.showSnackBar(SnackBar(content: Text(msg)));
      nav.pop();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: GradientBackground(
          child: SafeArea(
            child: ListView(padding: const EdgeInsets.all(16), children: [
              Row(children: [
                IconButton(tooltip: 'Back', onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.arrow_back, color: C.ink)),
                const Text('Report a concern', style: hTitle),
              ]),
              const Padding(padding: EdgeInsets.fromLTRB(12, 4, 12, 16), child: Text('About a place, not a person.', style: hSmall)),
              const Glass(child: Text('Pin placed on the map. It is matched to the nearest road.', style: TextStyle(fontWeight: FontWeight.w600))),
              const SizedBox(height: 20),
              const Text('What is the concern?', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [for (final e in _cats.entries) Pill(e.value, selected: cat == e.key, onTap: () => setState(() => cat = e.key))]),
              const SizedBox(height: 20),
              const Text('When does it happen?', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Row(children: [
                Pill('Day', selected: when == 'day', onTap: () => setState(() => when = 'day')),
                const SizedBox(width: 8),
                Pill('Night', selected: when == 'night', onTap: () => setState(() => when = 'night')),
              ]),
              const SizedBox(height: 20),
              TextField(
                controller: note,
                maxLength: 140,
                minLines: 2,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Short note (optional). No names or photos.',
                  filled: true,
                  fillColor: C.glass,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
              const SizedBox(height: 12),
              PrimaryButton(sending ? 'Sending...' : 'Submit report', onPressed: sending ? null : _submit),
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('The same report within 24 hours counts once. A red flag appears only after 3 or more people report and a moderator reviews.', style: hSmall),
              ),
            ]),
          ),
        ),
      );
}
