import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state.dart';
import '../theme.dart';
import '../widgets/glass.dart';

class RoutesScreen extends StatelessWidget {
  const RoutesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final routes = (s.comparison?['routes'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    return SafeArea(
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 20, 16, 120), children: [
        const Text('Compare routes', style: hTitle),
        const Padding(padding: EdgeInsets.fromLTRB(0, 4, 0, 12), child: Text('Concern, signal, isolation and time in one score. Lower is better.', style: hSmall)),
        Row(children: [
          Pill('Day', selected: s.mode == 'day', onTap: () => s.setMode('day')),
          const SizedBox(width: 8),
          Pill('Night', selected: s.mode == 'night', onTap: () => s.setMode('night')),
        ]),
        if (s.busy) const Padding(padding: EdgeInsets.only(top: 16), child: LinearProgressIndicator()),
        if (s.error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(s.error!, style: const TextStyle(color: C.red, fontWeight: FontWeight.w600))),
        for (final r in routes) _RouteCard(r),
        if (s.comparison != null) ...[
          const SizedBox(height: 12),
          Text(s.comparison!['explanation'] as String, style: const TextStyle(fontSize: 15, height: 1.4)),
          const SizedBox(height: 16),
          PrimaryButton('Start guarded trip', onPressed: () => s.setTab(2)),
          const SizedBox(height: 8),
          const GlassButton('Save offline (coming in the offline step)'),
          const SizedBox(height: 12),
          Text(s.comparison!['disclaimer'] as String, style: const TextStyle(fontSize: 12, color: C.body)),
        ],
      ]),
    );
  }
}

class _RouteCard extends StatelessWidget {
  const _RouteCard(this.r);
  final Map<String, dynamic> r;

  static const _terms = [('S', 'Concern', C.amber), ('N', 'Signal', C.navy), ('I', 'Isolation', C.accent), ('D', 'Time', Color(0xFF7C8BA8))];

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final rec = r['recommended'] == true;
    final isSelected = s.selectedRouteId == r['id'];
    final terms = r['terms'] as Map<String, dynamic>;
    final unmeasured = (r['unmeasured_signal_fraction'] as num?) ?? 0;

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: () => s.selectRoute(r['id'] as String),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: isSelected ? C.accent : (rec ? C.accent.withValues(alpha: 0.5) : Colors.transparent),
              width: isSelected ? 2.5 : (rec ? 1.5 : 0),
            ),
          ),
          child: Glass(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(r['name'] as String, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
                if (isSelected)
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: C.accent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(16), border: Border.all(color: C.accent)),
                    child: const Text('Selected', style: TextStyle(color: C.accent, fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
                if (rec)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: C.accent, borderRadius: BorderRadius.circular(20)),
                    child: const Text('Recommended', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
              ]),
              Text('${(r['minutes'] as num).round()} min | ${(r['km'] as num).toStringAsFixed(1)} km | Score ${(r['score'] as num).toStringAsFixed(3)}', style: hSmall),
              for (final t in _terms)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(children: [
                    SizedBox(width: 72, child: Text(t.$2, style: hSmall)),
                    Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(minHeight: 8, value: ((terms[t.$1] as num).toDouble()).clamp(0.0, 1.0), color: t.$3, backgroundColor: const Color(0x1F1F1B55)))),
                    SizedBox(width: 44, child: Text((terms[t.$1] as num).toStringAsFixed(2), textAlign: TextAlign.right, style: hSmall)),
                  ]),
                ),
              if (unmeasured > 0)
                Padding(padding: const EdgeInsets.only(top: 8), child: Text('${(unmeasured * 100).round()}% of this route has no signal data (treated as unknown).', style: hSmall)),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () {
                      s.selectRoute(r['id'] as String);
                      s.setTab(0);
                    },
                    icon: const Icon(Icons.map_outlined, size: 16, color: C.accent),
                    label: const Text('View on map', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: C.accent)),
                  ),
                ],
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
