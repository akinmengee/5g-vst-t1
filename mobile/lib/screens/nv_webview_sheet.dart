import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/nv_session.dart';
import '../state/session_controller.dart';
import '../theme/app_theme.dart';

/// mobile-integration.md § 2.1: `authorize_url` olduğu gibi uygulama-içi
/// WebView'de açılır; backend'in yönlendirmelerini WebView kendi takip eder,
/// biz hiçbir URL parse etmeyiz. SessionController arka planda
/// `/api/auth/status` polluyor — sonuç gelince (`pendingAuthorizeUrl` null
/// olunca) bu ekran kendini otomatik kapatır.
class NvWebViewSheet extends StatefulWidget {
  final String authorizeUrl;

  const NvWebViewSheet({super.key, required this.authorizeUrl});

  @override
  State<NvWebViewSheet> createState() => _NvWebViewSheetState();
}

class _NvWebViewSheetState extends State<NvWebViewSheet> {
  late final WebViewController _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => _loading = true),
          onPageFinished: (_) => setState(() => _loading = false),
        ),
      )
      ..loadRequest(Uri.parse(widget.authorizeUrl));
  }

  @override
  Widget build(BuildContext context) {
    // Backend status'ü "verified/rejected/error" olunca (pendingAuthorizeUrl
    // temizlenince) bu sheet kendini kapatır.
    final controller = context.watch<SessionController>();
    if (controller.pendingAuthorizeUrl == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
      });
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.navy,
        foregroundColor: Colors.white,
        title: const Text('Numara Doğrulanıyor'),
        actions: [
          TextButton(
            // İptal mantığı burada değil: sheet hangi yolla kapanırsa kapansın
            // NvScreen'in push(...).then(...) bloğu cancelPendingLogin çağırır.
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('İptal', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading || controller.nvSession.status == NvStatus.pending)
            const Positioned.fill(
              child: IgnorePointer(
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }
}
