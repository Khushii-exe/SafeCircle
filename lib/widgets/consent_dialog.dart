import 'package:flutter/material.dart';
import '../theme.dart';
import 'glass.dart';

class ConsentDialog extends StatefulWidget {
  const ConsentDialog({super.key, required this.onAccept});
  final VoidCallback onAccept;

  @override
  State<ConsentDialog> createState() => _ConsentDialogState();
}

class _ConsentDialogState extends State<ConsentDialog> {
  bool _acknowledged = true;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Glass(
        radius: 28,
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: C.accent.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.shield_outlined, color: C.accent, size: 28),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Welcome to SafeCircle', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: C.ink)),
                        Text('Delhi & Haryana Pilot • DPDP Principles', style: TextStyle(fontSize: 12, color: C.body, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Before you start, please review our core safety and privacy commitments:',
                style: TextStyle(fontSize: 13, color: C.body, height: 1.4),
              ),
              const SizedBox(height: 12),
              _principle(
                icon: Icons.place_outlined,
                title: 'Places, Never People',
                desc: 'Reports describe physical environments (lighting, isolation, obstacles). No names, photos, or people descriptions are collected.',
              ),
              _principle(
                icon: Icons.visibility_outlined,
                title: 'No False Green Routes',
                desc: 'Roads without reports are marked "no data / unknown", never "safe". Absence of reports is not proof of safety.',
              ),
              _principle(
                icon: Icons.lock_outline,
                title: 'Pseudonymous & Opt-In',
                desc: 'Your account uses pseudonymous identifiers. Background location is only accessed during an active Guarded Trip.',
              ),
              _principle(
                icon: Icons.bluetooth_searching,
                title: 'Rotating Bluetooth Tokens',
                desc: 'Nearby device evidence uses rotating ephemeral tokens. Encounters are unverified leads, never proof of presence.',
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () => setState(() => _acknowledged = !_acknowledged),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Checkbox(
                        value: _acknowledged,
                        activeColor: C.accent,
                        onChanged: (v) => setState(() => _acknowledged = v ?? true),
                      ),
                      const Expanded(
                        child: Text(
                          'I understand SafeCircle aids informed decisions and cannot guarantee safety or prevent crime.',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: C.ink),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              PrimaryButton(
                'Accept & Continue',
                color: _acknowledged ? C.ink : Colors.grey,
                onPressed: _acknowledged ? widget.onAccept : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _principle({required IconData icon, required String title, required String desc}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: C.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: C.ink)),
                const SizedBox(height: 2),
                Text(desc, style: const TextStyle(fontSize: 12, color: C.body, height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
