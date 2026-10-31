import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../state.dart';
import '../theme.dart';
import '../widgets/glass.dart';
import 'report_screen.dart';

class MapScreen extends StatelessWidget {
  const MapScreen({super.key});

  List<Polyline> _lines(AppState s) {
    final out = <Polyline>[];
    List<LatLng> pts(Map<String, dynamic> seg) => [for (final p in seg['geom'] as List) LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble())];

    // 1. Signal coverage layer
    if (s.showSignal) {
      for (final seg in s.segments) {
        switch (seg['signal']) {
          case 'weak':
            out.add(Polyline(points: pts(seg), strokeWidth: 14, color: C.navy.withValues(alpha: 0.30)));
          case 'none':
            out.add(Polyline(points: pts(seg), strokeWidth: 14, color: C.navy.withValues(alpha: 0.55)));
          case null:
            // Not measured = unknown, drawn as a thin dotted grey line, never as "good".
            out.add(Polyline(points: pts(seg), strokeWidth: 3, color: const Color(0x99000000), pattern: const StrokePattern.dotted()));
        }
      }
    }

    // 2. Community concern layer
    if (s.showConcern) {
      for (final seg in s.segments) {
        if (seg['concern'] == 'amber') out.add(Polyline(points: pts(seg), strokeWidth: 6, color: C.amber));
        if (seg['concern'] == 'red') out.add(Polyline(points: pts(seg), strokeWidth: 6, color: C.red));
      }
    }

    // 3. Selected route overlay (vivid blue with white outline)
    final sel = s.selectedRoute;
    if (sel != null && sel['coords'] is List) {
      final rawCoords = sel['coords'] as List;
      final routePts = [for (final p in rawCoords) LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble())];
      if (routePts.length >= 2) {
        out.add(Polyline(points: routePts, strokeWidth: 10, color: Colors.white.withValues(alpha: 0.85)));
        out.add(Polyline(points: routePts, strokeWidth: 6, color: C.accent));
      }
    }

    return out;
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final sel = s.selectedRoute;
    List<LatLng>? routePts;
    if (sel != null && sel['coords'] is List) {
      final rawCoords = sel['coords'] as List;
      routePts = [for (final p in rawCoords) LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble())];
    }

    return Stack(children: [
      FlutterMap(
        mapController: s.mapController,
        options: MapOptions(
          initialCenter: regionCenter,
          initialZoom: 10,
          minZoom: 7,
          maxZoom: 18,
          cameraConstraint: CameraConstraint.contain(bounds: regionBounds), // pan stays inside Delhi and Haryana
          onTap: (_, p) => s.setPin(p),
        ),
        children: [
          // Dev only. For the pilot, serve tiles from your own server (OSM tile policy forbids bulk use).
          TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'in.safecircle.app'),
          PolylineLayer(polylines: _lines(s)),
          const RichAttributionWidget(attributions: [TextSourceAttribution('OpenStreetMap contributors')]),
          MarkerLayer(markers: [
            if (s.me != null)
              Marker(
                point: s.me!,
                width: 24,
                height: 24,
                child: Container(
                  decoration: BoxDecoration(
                    color: C.accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                ),
              ),
            if (routePts != null && routePts.isNotEmpty) ...[
              Marker(
                point: routePts.first,
                width: 28,
                height: 28,
                child: Container(
                  decoration: BoxDecoration(color: const Color(0xFF1B8A44), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                  child: const Icon(Icons.trip_origin, color: Colors.white, size: 16),
                ),
              ),
              Marker(
                point: routePts.last,
                width: 32,
                height: 32,
                alignment: Alignment.topCenter,
                child: const Icon(Icons.flag_rounded, color: C.accent, size: 30),
              ),
            ],
            if (s.pin != null)
              Marker(
                point: s.pin!,
                width: 44,
                height: 44,
                alignment: Alignment.topCenter,
                child: const Icon(Icons.location_on, color: C.red, size: 44),
              ),
          ]),
        ],
      ),
      SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (s.isOffline)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: C.amber.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.wifi_off, size: 16, color: Colors.white),
                  SizedBox(width: 8),
                  Text('Offline — showing cached map snapshot', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                ]),
              ),
            Glass(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: InkWell(
                onTap: () => s.setTab(1),
                child: Row(children: [
                  const Icon(Icons.search, color: C.body),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      s.language == 'en' ? 'Where to?  Compare routes' : 'कहाँ जाना है? मार्ग तुलना करें',
                      style: const TextStyle(color: C.body, fontSize: 16),
                    ),
                  ),
                  InkWell(
                    onTap: s.toggleLanguage,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: C.glass, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.glassBorder)),
                      child: Text(s.language == 'en' ? 'हिन्दी' : 'EN', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: C.ink)),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 6, children: [
              Pill(s.language == 'en' ? 'Concerns' : 'सुरक्षा समस्याएं', selected: s.showConcern, onTap: s.toggleConcern, dot: C.amber),
              Pill(s.language == 'en' ? 'Weak signal' : 'कमज़ोर सिग्नल', selected: s.showSignal, onTap: s.toggleSignal, dot: C.navy),
              Pill('Demo: Pin A3', selected: false, onTap: s.setDemoA3Pin, dot: C.red),
            ]),
            const SizedBox(height: 8),
            SizedBox(
              height: 48,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                for (final p in s.places) Padding(padding: const EdgeInsets.only(right: 8), child: Pill(p.name, selected: false, onTap: () => s.jumpTo(p))),
              ]),
            ),
            if (s.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Glass(child: Text(s.error!, style: const TextStyle(color: C.red, fontWeight: FontWeight.w600))),
              ),
          ]),
        ),
      ),
      Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 104),
          child: Glass(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (sel != null) ...[
                InkWell(
                  onTap: () => s.setTab(1),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: C.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: C.accent.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.navigation, color: C.accent, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Active route: ${sel['name']} (${(sel['minutes'] as num).round()} min, ${(sel['km'] as num).toStringAsFixed(1)} km)',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: C.ink),
                          ),
                        ),
                        const Text('Change', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: C.accent)),
                      ],
                    ),
                  ),
                ),
              ],
              Row(children: [
                Expanded(
                  child: Text(
                    s.language == 'en' ? 'Night Safety Mode' : 'नाइट सेफ्टी मोड',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                ),
                Switch(value: s.mode == 'night', onChanged: (v) => s.setMode(v ? 'night' : 'day')),
              ]),
              const Text('Wide blue = weak signal. Dotted grey = not measured. No colour on a road means no data, never safe.', style: hSmall),
              const SizedBox(height: 12),
              PrimaryButton(
                s.pin == null
                    ? (s.language == 'en' ? 'Tap the map, then report a concern' : 'मानचित्र छुएं, फिर चिंता दर्ज करें')
                    : (s.language == 'en' ? 'Report a concern here' : 'यहाँ समस्या रिपोर्ट करें'),
                onPressed: s.pin == null ? null : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReportScreen())),
              ),
            ]),
          ),
        ),
      ),
    ]);
  }
}
