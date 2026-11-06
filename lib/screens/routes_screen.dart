import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../state.dart';
import '../theme.dart';
import '../widgets/glass.dart';

// ------------------------------------------------------------------ geocoding

const _nominatimBase = 'https://nominatim.openstreetmap.org/search';

Future<List<_Suggestion>> _geocode(String query) async {
  if (query.trim().length < 2) return [];
  try {
    final uri = Uri.parse('$_nominatimBase?q=${Uri.encodeQueryComponent(query)}&format=json&countrycodes=in&limit=5');
    final res = await http.get(uri, headers: {'User-Agent': 'SafeCircle/1.0'}).timeout(const Duration(seconds: 6));
    if (res.statusCode != 200) return [];
    final list = jsonDecode(utf8.decode(res.bodyBytes)) as List;
    return list.map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      return _Suggestion(
        label: m['display_name'] as String,
        lat: double.parse(m['lat'] as String),
        lon: double.parse(m['lon'] as String),
      );
    }).toList();
  } catch (_) {
    return [];
  }
}

class _Suggestion {
  _Suggestion({required this.label, required this.lat, required this.lon});
  final String label;
  final double lat;
  final double lon;
}

// ------------------------------------------------------------------ screen

class RoutesScreen extends StatefulWidget {
  const RoutesScreen({super.key});
  @override
  State<RoutesScreen> createState() => _RoutesScreenState();
}

class _RoutesScreenState extends State<RoutesScreen> {
  final _textCtrl = TextEditingController();
  final _focus = FocusNode();
  List<_Suggestion> _suggestions = [];
  bool _searching = false;
  Timer? _debounce;
  bool _showDropdown = false;

  @override
  void dispose() {
    _textCtrl.dispose();
    _focus.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _suggestions = [];
        _showDropdown = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      setState(() => _searching = true);
      final res = await _geocode(query);
      if (mounted) {
        setState(() {
          _suggestions = res;
          _showDropdown = res.isNotEmpty;
          _searching = false;
        });
      }
    });
  }

  void _selectSuggestion(_Suggestion s, AppState state) {
    _textCtrl.text = s.label.split(',').first.trim();
    _focus.unfocus();
    setState(() {
      _suggestions = [];
      _showDropdown = false;
    });
    state.setDestination(LatLng(s.lat, s.lon), s.label.split(',').first.trim());
  }

  void _clearDestination(AppState state) {
    _textCtrl.clear();
    setState(() {
      _suggestions = [];
      _showDropdown = false;
    });
    state.clearDestination();
    _focus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final routes = (s.comparison?['routes'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    return SafeArea(
      child: Stack(
        children: [
          ListView(padding: const EdgeInsets.fromLTRB(16, 20, 16, 120), children: [
            const Text('Compare routes', style: hTitle),
            const Padding(
              padding: EdgeInsets.fromLTRB(0, 4, 0, 12),
              child: Text('Concern, signal, isolation and time in one score. Lower is better.', style: hSmall),
            ),

            // ---- Origin / Source field ----
            _SourceField(
              sourceName: s.sourceName,
              currentLoc: s.me,
              onDetectLocation: () => s.detectCurrentLocationAsSource(),
              onClear: s.sourceLocation != null ? () => s.clearSource() : null,
            ),
            const SizedBox(height: 8),

            // ---- Destination search box ----
            _DestinationSearchField(
              controller: _textCtrl,
              focusNode: _focus,
              onChanged: _onSearchChanged,
              searching: _searching,
              onClear: s.destinationName != null ? () => _clearDestination(s) : null,
              destinationName: s.destinationName,
            ),

            // ---- City chips ----
            const SizedBox(height: 10),
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: s.places.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final p = s.places[i];
                  final selected = s.destinationName == p.name;
                  return Pill(p.name, selected: selected, onTap: () {
                    if (selected) {
                      _clearDestination(s);
                    } else {
                      _textCtrl.text = p.name;
                      s.setDestination(p.at, p.name);
                      _focus.unfocus();
                      setState(() { _showDropdown = false; _suggestions = []; });
                    }
                  });
                },
              ),
            ),
            const SizedBox(height: 12),

            // ---- Mode pills ----
            Row(children: [
              Pill('Day', selected: s.mode == 'day', onTap: () => s.setMode('day')),
              const SizedBox(width: 8),
              Pill('Night', selected: s.mode == 'night', onTap: () => s.setMode('night')),
              const Spacer(),
              if (routes.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: C.accent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(16), border: Border.all(color: C.accent)),
                  child: Text('${routes.length} route${routes.length == 1 ? "" : "s"} found', style: const TextStyle(color: C.accent, fontSize: 12, fontWeight: FontWeight.w700)),
                ),
            ]),

            // ---- Offline banner ----
            if (s.isShowingOfflineRoute && s.offlineRouteTime != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: C.amber.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12), border: Border.all(color: C.amber)),
                  child: Row(children: [
                    const Icon(Icons.wifi_off, color: C.amber, size: 16),
                    const SizedBox(width: 8),
                    Expanded(child: Text('Offline snapshot from ${_formatSnapshotTime(s.offlineRouteTime!)}', style: const TextStyle(fontSize: 13, color: C.amber, fontWeight: FontWeight.w600))),
                  ]),
                ),
              ),

            if (s.busy) const Padding(padding: EdgeInsets.only(top: 16), child: LinearProgressIndicator()),
            if (s.error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(s.error!, style: const TextStyle(color: C.red, fontWeight: FontWeight.w600))),
            for (final r in routes) _RouteCard(r),
            if (s.comparison != null) ...[
              const SizedBox(height: 12),
              Text(s.comparison!['explanation'] as String, style: const TextStyle(fontSize: 15, height: 1.4)),
              const SizedBox(height: 16),
              PrimaryButton('Start guarded trip', onPressed: () => s.setTab(2)),
              const SizedBox(height: 8),
              GlassButton('Save for offline', onPressed: () async {
                await s.saveOfflineRoute();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Route saved for offline use.')));
                }
              }),
              const SizedBox(height: 12),
              Text(s.comparison!['disclaimer'] as String, style: const TextStyle(fontSize: 12, color: C.body)),
            ],
            const _MetricsExplanationCard(),
          ]),

          // ---- Dropdown overlay ----
          if (_showDropdown)
            Positioned(
              top: 110,
              left: 16,
              right: 16,
              child: Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(16),
                color: Colors.white,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final sug in _suggestions)
                      InkWell(
                        onTap: () => _selectSuggestion(sug, s),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Row(children: [
                            const Icon(Icons.location_on_outlined, color: C.accent, size: 18),
                            const SizedBox(width: 10),
                            Expanded(child: Text(sug.label.split(',').take(2).join(', '), style: const TextStyle(fontSize: 14, color: C.ink))),
                          ]),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String _formatSnapshotTime(DateTime t) {
  final diff = DateTime.now().difference(t);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes} min ago';
  if (diff.inDays < 1) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

// ------------------------------------------------------------------ source & search fields

class _SourceField extends StatelessWidget {
  const _SourceField({
    required this.sourceName,
    required this.currentLoc,
    required this.onDetectLocation,
    this.onClear,
  });

  final String? sourceName;
  final LatLng? currentLoc;
  final VoidCallback onDetectLocation;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final displayName = sourceName ?? (currentLoc != null ? 'Current Location (GPS)' : 'Cyber City, Gurugram');
    final isDetected = sourceName != null || currentLoc != null;

    return Glass(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.trip_origin, color: isDetected ? const Color(0xFF2E7D32) : C.body, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('FROM', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: C.body, letterSpacing: 0.8)),
                Text(
                  displayName,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isDetected ? FontWeight.w700 : FontWeight.w500,
                    color: isDetected ? C.ink : C.body,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          InkWell(
            onTap: onDetectLocation,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF2E7D32).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF2E7D32).withValues(alpha: 0.4)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.my_location, size: 13, color: Color(0xFF2E7D32)),
                  SizedBox(width: 4),
                  Text('Detect location', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF2E7D32))),
                ],
              ),
            ),
          ),
          if (onClear != null)
            IconButton(
              icon: const Icon(Icons.close, size: 16, color: C.body),
              onPressed: onClear,
              padding: const EdgeInsets.only(left: 4),
              constraints: const BoxConstraints(),
            ),
        ],
      ),
    );
  }
}

class _DestinationSearchField extends StatelessWidget {
  const _DestinationSearchField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.searching,
    this.onClear,
    this.destinationName,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final bool searching;
  final VoidCallback? onClear;
  final String? destinationName;

  @override
  Widget build(BuildContext context) {
    return Glass(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(children: [
        const Icon(Icons.search, color: C.accent),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            onChanged: onChanged,
            style: const TextStyle(fontSize: 15, color: C.ink),
            decoration: InputDecoration(
              hintText: 'Enter destination…',
              hintStyle: const TextStyle(color: C.body),
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
              suffixIcon: searching ? const SizedBox(width: 18, height: 18, child: Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator(strokeWidth: 2))) : null,
            ),
          ),
        ),
        if (onClear != null)
          IconButton(icon: const Icon(Icons.close, size: 18, color: C.body), onPressed: onClear, padding: EdgeInsets.zero, constraints: const BoxConstraints()),
      ]),
    );
  }
}

// ------------------------------------------------------------------ route card

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
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Select button.
                  FilledButton.tonal(
                    onPressed: () => s.selectRoute(r['id'] as String),
                    style: FilledButton.styleFrom(
                      backgroundColor: isSelected ? C.accent.withValues(alpha: 0.15) : C.glass,
                      foregroundColor: C.accent,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      shape: const StadiumBorder(),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      minimumSize: Size.zero,
                      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                    child: Text(isSelected ? '✓ Selected' : 'Select'),
                  ),
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

// ------------------------------------------------------------------ metrics explanation

class _MetricsExplanationCard extends StatelessWidget {
  const _MetricsExplanationCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 18),
      child: Glass(
        radius: 24,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [
              Icon(Icons.help_outline_rounded, color: C.accent, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text('Understanding Route Safety Symbols', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: C.ink)),
              ),
            ]),
            const SizedBox(height: 12),
            _metricItem(
              'S',
              'Concern Score',
              'Safety hazard index based on community reports (dark stretches, lack of lighting, aggressive stray animals, abandoned zones, bad residents). 0.00 is clear; higher numbers reflect reported safety hazards along this road.',
              C.amber,
            ),
            const SizedBox(height: 10),
            _metricItem(
              'N',
              'Mobile Signal Risk',
              'Cellular network vulnerability. High scores mean cellular dead zones where SOS emergency dispatches, live trip location sharing, and calls for help may drop.',
              C.navy,
            ),
            const SizedBox(height: 10),
            _metricItem(
              'I',
              'Isolation Index',
              'Physical road solitude. Measures distance from open 24/7 commercial establishments, streetlights, and active pedestrian surveillance.',
              C.accent,
            ),
            const SizedBox(height: 10),
            _metricItem(
              'D',
              'Time / Delay Penalty',
              'Extra travel detour compared to the fastest possible route. 0.00 indicates the quickest path; higher values show added travel time to bypass hazardous stretches.',
              const Color(0xFF7C8BA8),
            ),
            const Divider(height: 24),
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: C.accent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
                child: const Text('Overall Score', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: C.accent)),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Weighted combination: R = wS·S + wN·N + wI·I + wD·D. A LOWER score is always safer.', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: C.ink)),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _metricItem(String code, String title, String desc, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.2), shape: BoxShape.circle, border: Border.all(color: color, width: 1.5)),
          child: Text(code, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: color)),
              const SizedBox(height: 2),
              Text(desc, style: const TextStyle(fontSize: 12, color: C.body, height: 1.35)),
            ],
          ),
        ),
      ],
    );
  }
}
