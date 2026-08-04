import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/nv_screen.dart';
import 'state/session_controller.dart';
import 'theme/app_theme.dart';

class TeknofestApp extends StatelessWidget {
  const TeknofestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => SessionController(),
      child: MaterialApp(
        title: 'TEKNOFEST 5G — VST T1',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: const NvScreen(),
      ),
    );
  }
}
