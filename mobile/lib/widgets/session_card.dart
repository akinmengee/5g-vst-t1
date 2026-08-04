import 'package:flutter/material.dart';

import '../models/nv_session.dart';
import '../theme/app_theme.dart';
import 'accent_card.dart';

/// Open Gateway Demo UX Kılavuzu → "02 Doğrulanmış oturumu görüntüle" /
/// HOME SEKMESİ · "SESSİON" KARTI.
class SessionCard extends StatelessWidget {
  final NvSession session;

  const SessionCard({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    return AccentCard(
      accentColor: session.isVerified ? Colors.green : Colors.grey.shade300,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const StepBadge('02'),
              const SizedBox(width: 8),
              const Icon(Icons.verified, color: Colors.green, size: 20),
              const SizedBox(width: 6),
              const Text('Verified', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          _row('Phone number', session.phoneNumber),
          _row('Flow ID', session.flowId ?? '-'),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Flexible(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
