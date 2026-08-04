import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/nv_session.dart';
import '../state/session_controller.dart';
import '../theme/app_theme.dart';

/// mobile-integration.md 2.1: `authorize_url` OLDUĞU GİBİ uygulama-içi
/// WebView'de açılır. Deep-link/URL parse YOK — Turkcell'in yönlendirme
/// zincirini WebView kendisi takip eder; sonuç status polling'den gelir ve
/// status `authorizing`dan çıktığı anda bu ekran kendini kapatır.
class NvWebViewScreen extends StatefulWidget {
  final String authorizeUrl;

  const NvWebViewScreen({super.key, required this.authorizeUrl});

  @override
  State<NvWebViewScreen> createState() => _NvWebViewScreenState();
}

class _NvWebViewScreenState extends State<NvWebViewScreen> {
  late final WebViewController _webViewController;
  bool _pageLoading = true;

  @override
  void initState() {
    super.initState();
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => _pageLoading = true),
          onPageFinished: (_) => setState(() => _pageLoading = false),
        ),
      )
      ..loadRequest(Uri.parse(widget.authorizeUrl));
  }

  @override
  Widget build(BuildContext context) {
    // Doğrulama sonuçlandığında (verified/rejected/failed) ekranı kapat —
    // "WebView'i programatik kapatma" şartının karşılığı.
    final status = context.select<SessionController, NvStatus>((c) => c.nvSession.status);
    if (status != NvStatus.authorizing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
    }

    return Scaffold(
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppTheme.headerGradient),
        ),
        title: const Text('Turkcell ile Doğrulama'),
        actions: [
          if (_pageLoading)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.turkcellYellow),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: AppTheme.navy.withValues(alpha: 0.05),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: const Row(
              children: [
                Icon(Icons.lock_outline, size: 14, color: AppTheme.inkSoft),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Şebeke üzerinden doğrulanıyor — bu pencere otomatik kapanacak',
                    style: TextStyle(fontSize: 12, color: AppTheme.inkSoft),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: WebViewWidget(controller: _webViewController)),
        ],
      ),
    );
  }
}
