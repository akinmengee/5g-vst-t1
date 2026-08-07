import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../models/nv_session.dart';
import '../state/session_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/hero_background.dart';
import 'home_screen.dart';
import 'nv_webview_screen.dart';

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
  bool _showLogs = false;
  bool _webViewOpen = false;

  // NvScreen, MaterialApp'ın `home:`'u olduğu için navigator stack'inin en
  // altında sabit duruyor — hiçbir zaman pop/dispose edilmiyor. Bu yüzden
  // context.watch<SessionController>() nedeniyle SessionController'daki HER
  // notifyListeners() (AI polling, kayıt sayacı, trace logu, bant genişliği
  // ölçümü — yani sürekli) bu widget'ı da yeniden build ediyordu. Bayrak
  // olmadan aşağıdaki postFrameCallback, `isVerified` true kaldığı SÜRECE
  // (doğrulamadan sonraki tüm oturum boyunca) her rebuild'de yeniden
  // `pushReplacement(HomeScreen())` çağırıyordu — kullanıcı AI Sonucu/İz
  // sekmesindeyken ya da kayıt ortasındayken araya bir arka plan güncellemesi
  // girerse, TAZE bir HomeScreen (TabController index 0'dan) en üste basılıp
  // kullanıcı "ilk kısma" (Akış sekmesine) fırlatılıyordu. Bayrak, yönlendirmeyi
  // doğrulama başına TAM BİR KEZ yapılmaya kilitliyor; logout ile nvSession
  // sıfırlanıp yeniden doğrulanınca (`!session.isVerified` anında) bayrak da
  // sıfırlanıyor, bir sonraki doğrulamada yönlendirme yine çalışır.
  bool _navigatedHome = false;

  @override
  void initState() {
    super.initState();
    // Varsayılan boş: yarışma günü elimizdeki SIM'in numarası girilecek.
    // `--dart-define=PHONE=+90...` verilmişse ülke kodu ayıklanıp doldurulur.
    final onDolu = AppConfig.varsayilanTelefon;
    _localNumberController = TextEditingController(
      text: onDolu.startsWith(_countryCode)
          ? onDolu.substring(_countryCode.length)
          : onDolu,
    );
  }

  @override
  void dispose() {
    _localNumberController.dispose();
    super.dispose();
  }

  Future<void> _openWebView(String authorizeUrl) async {
    _webViewOpen = true;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => NvWebViewScreen(authorizeUrl: authorizeUrl)),
    );
    _webViewOpen = false;
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SessionController>();
    final session = controller.nvSession;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // authorize_url geldiyse sözleşme gereği uygulama-içi WebView'de açılır
      // (Turkcell'in kendi onay/doğrulama sayfası, hücresel ağ üzerinden).
      if (session.status == NvStatus.authorizing &&
          session.authorizeUrl != null &&
          !_webViewOpen) {
        _openWebView(session.authorizeUrl!);
      }
      // Numara başarıyla doğrulandığında ekran yumuşak geçişle (auth-gate) ana
      // uygulamaya açılır — yalnızca BİR KEZ (bkz. _navigatedHome dokümantasyonu).
      // Geçiş, arka plandaki "doğrulandı" ışık patlamasının (bkz. HeroHeader
      // SignalMood.verified) görünür olması için ~550ms geciktiriliyor —
      // patlama 650ms sürüyor, gecikme onun büyük kısmını ekranda tutuyor.
      if (session.isVerified && !_navigatedHome) {
        _navigatedHome = true;
        // Navigator, gecikmeli callback'te BuildContext'i async gap sonrası
        // kullanmamak için ÖNCEDEN (senkron) yakalanıyor.
        final navigator = Navigator.of(context);
        Future.delayed(const Duration(milliseconds: 550), () {
          if (!mounted) return;
          navigator.pushReplacement(fadeSlideRoute(const HomeScreen()));
        });
      } else if (!session.isVerified) {
        _navigatedHome = false;
      }
    });

    return Scaffold(
      backgroundColor: AppTheme.navy,
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.headerGradient),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: HeroHeader(
                        titleWhite: 'VST-T1',
                        titleYellow: '5G',
                        subtitle: 'Sürücü davranış analizi',
                        mood: switch (session.status) {
                          NvStatus.authorizing => SignalMood.connecting,
                          NvStatus.verified => SignalMood.verified,
                          NvStatus.idle ||
                          NvStatus.rejected ||
                          NvStatus.failed =>
                            SignalMood.idle,
                        },
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: _FormSheet(
                        controller: controller,
                        localNumberController: _localNumberController,
                        showLogs: _showLogs,
                        onToggleLogs: () => setState(() => _showLogs = !_showLogs),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FormSheet extends StatelessWidget {
  final SessionController controller;
  final TextEditingController localNumberController;
  final bool showLogs;
  final VoidCallback onToggleLogs;

  const _FormSheet({
    required this.controller,
    required this.localNumberController,
    required this.showLogs,
    required this.onToggleLogs,
  });

  void _submit() {
    final full = '$_countryCode${localNumberController.text.trim()}';
    controller.submitPhoneNumber(full);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            const BorderRadius.only(topLeft: Radius.circular(28), topRight: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 30,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(24, 10, 24, MediaQuery.of(context).padding.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            children: const [
              StepBadge('01'),
              SizedBox(width: 8),
              Text('Numaranı doğrula',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Şebeke üzerinden doğrulanır, SMS kodu gelmez',
            style: TextStyle(color: AppTheme.inkSoft, fontSize: 12.5),
          ),
          const SizedBox(height: 20),
          Container(
            decoration: BoxDecoration(
              color: AppTheme.background,
              border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Text(_countryCode,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: AppTheme.ink,
                      fontFeatures: [FontFeature.tabularFigures()],
                    )),
                const SizedBox(width: 10),
                Container(width: 1, height: 26, color: Colors.black.withValues(alpha: 0.10)),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: localNumberController,
                    keyboardType: TextInputType.phone,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      filled: false,
                      hintText: '555 111 22 33',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 15),
                    ),
                  ),
                ),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: localNumberController,
                  builder: (context, value, _) {
                    if (value.text.isEmpty) return const SizedBox.shrink();
                    return IconButton(
                      icon: const Icon(Icons.close, size: 18, color: AppTheme.inkSoft),
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
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.turkcellYellow,
                foregroundColor: AppTheme.navy,
                disabledBackgroundColor: AppTheme.turkcellYellow.withValues(alpha: 0.55),
                disabledForegroundColor: AppTheme.navy.withValues(alpha: 0.65),
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              onPressed:
                  (controller.nvLoading || controller.nvSession.status == NvStatus.authorizing)
                      ? null
                      : _submit,
              child: controller.nvLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.navy))
                  : controller.nvSession.status == NvStatus.authorizing
                      ? const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: AppTheme.navy)),
                            SizedBox(width: 10),
                            Text('Şebekeden doğrulanıyor…'),
                          ],
                        )
                      : const Text('Doğrula'),
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.verified_user, size: 14, color: AppTheme.success),
                SizedBox(width: 5),
                Text(
                  'Turkcell Number Verification',
                  style: TextStyle(
                      fontSize: 11, color: AppTheme.inkSoft, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          if (controller.nvSession.status == NvStatus.failed ||
              controller.nvSession.status == NvStatus.rejected) ...[
            const SizedBox(height: 16),
            // Sözleşme 2.3: WiFi hatası sahada en olası hata — özel mesajı var.
            if (controller.nvSession.isWifiError)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF6E8),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.warning.withValues(alpha: 0.35)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.wifi_off, color: AppTheme.warning, size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'WiFi\'yi kapatıp mobil veriyi açın, sonra yeniden deneyin — '
                        'doğrulama yalnızca hücresel ağ üzerinden çalışır.',
                        style: TextStyle(fontSize: 12.5, height: 1.35),
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFDECEC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.danger.withValues(alpha: 0.25)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: AppTheme.danger, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        controller.nvSession.status == NvStatus.rejected
                            ? 'Numara bu cihazla eşleşmedi'
                            : 'Giriş başarısız',
                        style: const TextStyle(fontSize: 12.5, color: AppTheme.danger),
                      ),
                    ),
                  ],
                ),
              ),
            TextButton(
              onPressed: onToggleLogs,
              child: const Text('Bağlantı kayıtları'),
            ),
            if (showLogs)
              Text(
                controller.nvSession.errorMessage ?? 'Bilinmeyen hata',
                style: const TextStyle(
                    fontSize: 11.5, color: AppTheme.inkSoft, fontFamily: AppTheme.monoFamily),
              ),
          ],
        ],
      ),
    );
  }
}
