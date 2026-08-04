import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../models/nv_session.dart';
import '../state/session_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/hero_background.dart';
import '../widgets/mock_mode_banner.dart';
import 'home_screen.dart';
import 'nv_webview_sheet.dart';

const _countryCode = '+90';

/// Open Gateway Demo UX Kılavuzu → "01 Numara Doğrulama ile giriş".
/// Hero (sinyal halkaları + yol motifi) üzerine oturan beyaz form kartı.
class NvScreen extends StatefulWidget {
  const NvScreen({super.key});

  @override
  State<NvScreen> createState() => _NvScreenState();
}

class _NvScreenState extends State<NvScreen> {
  late final TextEditingController _localNumberController;
  bool _webViewOpen = false;

  @override
  void initState() {
    super.initState();
    final sandbox = AppConfig.sandboxTestPhoneNumber;
    _localNumberController = TextEditingController(
      text: sandbox.startsWith(_countryCode) ? sandbox.substring(_countryCode.length) : sandbox,
    );
  }

  @override
  void dispose() {
    _localNumberController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SessionController>();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Numara başarıyla doğrulandığında ekran çapraz geçişle (auth-gate)
      // ana uygulamaya açılır.
      if (controller.nvSession.isVerified) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
        return;
      }
      // mobile-integration.md § 2.1: authorize_url gelince uygulama-içi
      // WebView'de açılır; SessionController arka planda status'ü polluyor,
      // sonuç gelince (pendingAuthorizeUrl null olunca) sheet kendini kapatır.
      final url = controller.pendingAuthorizeUrl;
      if (url != null && !_webViewOpen) {
        _webViewOpen = true;
        Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => NvWebViewSheet(authorizeUrl: url)))
            .then((_) => _webViewOpen = false);
      }
    });

    return Scaffold(
      backgroundColor: AppTheme.navy,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (AppConfig.useMock) const MockModeBanner(),
            Expanded(
              child: Stack(
                children: [
                  const Positioned.fill(
                    child: HeroHeader(
                      titleWhite: 'TEKNOFEST',
                      titleYellow: '5G',
                      subtitle: 'Sürücü davranış analizi',
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: _FormSheet(
                      controller: controller,
                      localNumberController: _localNumberController,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FormSheet extends StatelessWidget {
  final SessionController controller;
  final TextEditingController localNumberController;

  const _FormSheet({required this.controller, required this.localNumberController});

  void _submit() {
    final digits = localNumberController.text.replaceAll(RegExp(r'\s+'), '');
    controller.submitPhoneNumber('$_countryCode$digits');
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = controller.nvLoading || controller.nvSession.status == NvStatus.pending;
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(topLeft: Radius.circular(28), topRight: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(24, 20, 24, MediaQuery.of(context).padding.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              StepBadge('01'),
              SizedBox(width: 8),
              Text('Numaranı doğrula', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Şebeke üzerinden doğrulanır, SMS kodu gelmez',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 20),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Text(_countryCode, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                const SizedBox(width: 10),
                Container(width: 1, height: 26, color: Colors.grey.shade300),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: localNumberController,
                    keyboardType: TextInputType.phone,
                    style: const TextStyle(fontSize: 16),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: '555 111 22 33',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: localNumberController,
                  builder: (context, value, _) {
                    if (value.text.isEmpty) return const SizedBox.shrink();
                    return IconButton(
                      icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                      onPressed: localNumberController.clear,
                      visualDensity: VisualDensity.compact,
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: isLoading ? null : _submit,
              child: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Doğrula'),
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.verified_user, size: 14, color: Colors.green.shade600),
                const SizedBox(width: 5),
                Text(
                  'Turkcell Number Verification',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          if (controller.nvSession.status == NvStatus.failed) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red.shade700, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      controller.nvSession.errorMessage ?? 'Doğrulama başarısız oldu.',
                      style: TextStyle(fontSize: 12.5, color: Colors.red.shade700),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
