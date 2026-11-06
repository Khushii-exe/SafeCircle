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
  String? _error;      // persistent inline error
  bool _submitted = false;

  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final s = context.read<AppState>();
    final nav = Navigator.of(context);
    setState(() { sending = true; _error = null; });
    try {
      final r = await s.submitReport(cat, when, note.text.trim());
      if (!mounted) return;
      // Build a human-readable success message
      final msgs = <String>[];
      if (r['counted'] == true) {
        msgs.add('Report added — thank you.');
      } else {
        msgs.add('You already reported this spot in the last 24 hours, so it counts once.');
      }
      if (r['pending_review'] == true) msgs.add('This place now needs moderator review.');
      if (r['verified_presence'] != true) msgs.add('Your location could not be confirmed, so the report carries less weight.');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msgs.join(' ')),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );
      setState(() => _submitted = true);
      await Future.delayed(const Duration(milliseconds: 400));
      nav.pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      // Translate known backend messages into user-friendly copy
      String friendly = e.message;
      if (e.message.contains('No road within')) {
        friendly = 'The pin is not on a road. Move it closer to a street and try again.';
      } else if (e.message.contains('already reported')) {
        friendly = 'You\'ve already reported this spot today — it counts once per 24 hours.';
      } else if (e.message.contains('limit')) {
        friendly = 'You\'ve reached the daily report limit. Try again tomorrow.';
      } else if (e.message.contains('region')) {
        friendly = 'SafeCircle currently only covers Delhi and Haryana. Move the pin inside the pilot area.';
      }
      setState(() { sending = false; _error = friendly; });
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
              // Inline error card with retry
              if (_error != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: C.red.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: C.red.withValues(alpha: 0.4)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Icon(Icons.error_outline, color: C.red, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_error!, style: const TextStyle(color: C.red, fontWeight: FontWeight.w600, fontSize: 14))),
                    ]),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 40,
                      child: OutlinedButton.icon(
                        onPressed: _submit,
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Try again'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: C.red,
                          side: const BorderSide(color: C.red),
                          shape: const StadiumBorder(),
                          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ]),
                ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: sending
                    ? const SizedBox(
                        height: 54,
                        key: ValueKey('spinner'),
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5)),
                          SizedBox(width: 12),
                          Text('Sending…', style: TextStyle(color: C.body, fontWeight: FontWeight.w600)),
                        ]),
                      )
                    : PrimaryButton(
                        _submitted ? 'Sent ✓' : 'Submit report',
                        key: const ValueKey('btn'),
                        onPressed: sending ? null : _submit,
                      ),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('The same report within 24 hours counts once. A red flag appears only after 3 or more people report and a moderator reviews.', style: hSmall),
              ),
            ]),
          ),
        ),
      );
}
