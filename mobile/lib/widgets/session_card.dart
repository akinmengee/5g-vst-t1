import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/nv_session.dart';
import '../theme/app_theme.dart';
import 'accent_card.dart';

/// Open Gateway Demo UX Kılavuzu → "02 Doğrulanmış oturumu görüntüle" /
/// HOME SEKMESİ · "SESSİON" KARTI.
class SessionCard extends StatefulWidget {
  final NvSession session;

  const SessionCard({super.key, required this.session});

  @override
  State<SessionCard> createState() => _SessionCardState();
}

class _SessionCardState extends State<SessionCard> {
  // flow_id varsayılan olarak GİZLİ — teknik bir kimlik, canlı demoda ekranı
  // gereksiz doldurmasın diye. Çentiğe (chevron) dokununca açılır.
  bool _flowIdAcik = false;

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
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
                    // Gruplu yazım ("+90 536 030 35 56") boşluklar yüzünden
                    // ham numaradan daha geniş — dar ekranlarda PillBadge'in
                    // yanında sığmayıp son grup ("56") alta sarıyordu.
                    // FittedBox tek satırda tutup gerekirse küçültüyor,
                    // hiçbir hane kaybolmuyor/kırpılmıyor.
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        session.formattedPhoneNumber,
                        maxLines: 1,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          letterSpacing: 0.3,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Şebeke üzerinden doğrulandı',
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
          const SizedBox(height: 10),
          // mobile-integration.md 3: flow_id tek ipliktir — sonraki tüm
          // adımlar (status/qod/upload) bu id ile bağlanır. Teknik bir
          // detay olduğu için varsayılan kapalı, çentikle açılır.
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _flowIdAcik = !_flowIdAcik),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  const Icon(Icons.link, size: 13, color: AppTheme.inkSoft),
                  const SizedBox(width: 6),
                  const Text('flow_id',
                      style: TextStyle(color: AppTheme.inkSoft, fontSize: 11.5)),
                  const Spacer(),
                  AnimatedRotation(
                    duration: const Duration(milliseconds: 200),
                    turns: _flowIdAcik ? 0.5 : 0,
                    child: const Icon(Icons.keyboard_arrow_down,
                        size: 18, color: AppTheme.inkSoft),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState: _flowIdAcik ? CrossFadeState.showFirst : CrossFadeState.showSecond,
            firstChild: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: InkWell(
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
                      Expanded(
                        child: Text(
                          session.flowId ?? '—',
                          overflow: TextOverflow.ellipsis,
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
            ),
            secondChild: const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}
