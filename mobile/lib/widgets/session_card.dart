import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
      accentColor: session.isVerified ? AppTheme.success : AppTheme.idle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const StepBadge('02'),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.phoneNumber,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Şebeke üzerinden doğrulandı — SMS kodu kullanılmadı',
                      style: TextStyle(color: AppTheme.inkSoft, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              const PillBadge(
                color: AppTheme.success,
                label: 'Doğrulandı',
                icon: Icons.verified,
                fontSize: 11.5,
              ),
            ],
          ),
          const SizedBox(height: 14),
          // mobile-integration.md 3: flow_id tek ipliktir — sonraki tüm
          // adımlar (status/qod/upload) bu id ile bağlanır.
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: session.flowId == null
                ? null
                : () {
                    Clipboard.setData(ClipboardData(text: session.flowId!));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Flow ID panoya kopyalandı')),
                    );
                  },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.background,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Text('flow_id',
                      style: TextStyle(color: AppTheme.inkSoft, fontSize: 11.5)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      session.flowId ?? '—',
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontFamily: AppTheme.monoFamily,
                        fontSize: 11.5,
                        color: AppTheme.ink,
                      ),
                    ),
                  ),
                  if (session.flowId != null) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.copy, size: 13, color: AppTheme.inkSoft),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
