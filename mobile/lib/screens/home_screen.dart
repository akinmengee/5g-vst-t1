import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../state/session_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/entrance.dart';
import '../widgets/mock_mode_banner.dart';
import '../widgets/qod_card.dart';
import '../widgets/session_card.dart';
import '../widgets/step_timeline.dart';
import '../widgets/video_card.dart';
import 'ai_result_screen.dart';
import 'nv_screen.dart';
import 'trace_tab.dart';

/// ÜST ÇUBUK: "OpenGW + numara + çıkış (logout)" — Open Gateway Demo UX
/// Kılavuzu, HOME SEKMESİ · "SESSİON" KARTI.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SessionController>();
    final onAiTab = _tabController.index == 1;

    return Scaffold(
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppTheme.headerGradient),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              controller.nvSession.phoneNumber,
              style: const TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            Text(
              'VST-T1 · 5G Yol Güvenliği',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
                color: Colors.white.withValues(alpha: 0.65),
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
        leading: Padding(
          padding: const EdgeInsets.only(left: 12, top: 6, bottom: 6),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.wifi_tethering, color: AppTheme.turkcellYellow, size: 20),
          ),
        ),
        actions: [
          if (onAiTab)
            IconButton(
              key: const Key('ai-result-refresh'),
              icon: const Icon(Icons.refresh),
              tooltip: 'Sonuçları yenile',
              onPressed: controller.aiLoading ? null : controller.refreshAiResults,
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Çıkış',
            onPressed: () {
              controller.logout();
              Navigator.of(context).pushReplacement(fadeSlideRoute(const NvScreen()));
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Akış'),
            Tab(text: 'AI Sonucu'),
            Tab(text: 'İz'),
          ],
        ),
      ),
      body: Column(
        children: [
          if (AppConfig.useMock) const MockModeBanner(),
          StepTimeline(currentStep: controller.currentStepIndex),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Entrance(child: SessionCard(session: controller.nvSession)),
                    const SizedBox(height: 12),
                    Entrance(
                      delayMs: 70,
                      child: QodCard(
                        session: controller.qodSession,
                        loading: controller.qodLoading,
                        onStart: () => controller.startQod(),
                        bandwidthBefore: controller.bandwidthBefore,
                        bandwidthAfter: controller.bandwidthAfter,
                        bandwidthMeasuring: controller.bandwidthMeasuring,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Entrance(
                      delayMs: 140,
                      child: VideoCard(
                        controller: controller,
                        onOpenResult: (jobId) {
                          controller.selectJob(jobId);
                          _tabController.animateTo(1);
                        },
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
                const AiResultTab(),
                TraceTab(traceLog: controller.traceLog),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
