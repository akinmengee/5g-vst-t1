import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../state/session_controller.dart';
import '../theme/app_theme.dart';
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
        titleSpacing: 12,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.signal_cellular_alt, color: AppTheme.turkcellYellow, size: 20),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('TEKNOFEST 5G', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                Text(
                  controller.nvSession.phoneNumber,
                  style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.7)),
                ),
              ],
            ),
          ],
        ),
        actions: [
          if (onAiTab)
            IconButton(
              key: const Key('ai-result-refresh'),
              icon: const Icon(Icons.refresh),
              onPressed: controller.aiLoading ? null : controller.refreshAiResult,
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Çıkış',
            onPressed: () {
              controller.logout();
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const NvScreen()),
              );
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Home'),
            Tab(text: 'AI Result'),
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
                    SessionCard(session: controller.nvSession),
                    const SizedBox(height: 12),
                    QodCard(
                      session: controller.qodSession,
                      loading: controller.qodLoading,
                      onStart: controller.startQod,
                      bandwidthBefore: controller.bandwidthBefore,
                      bandwidthAfter: controller.bandwidthAfter,
                      bandwidthMeasuring: controller.bandwidthMeasuring,
                    ),
                    const SizedBox(height: 12),
                    VideoCard(controller: controller),
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
