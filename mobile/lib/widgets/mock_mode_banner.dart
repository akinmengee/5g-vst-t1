import 'package:flutter/material.dart';

/// AppConfig.useMock = true iken hangi verinin gerçek, hangisinin sahte
/// olduğunu ekranda görünür şekilde belirtir. Amaç: kimse (takım arkadaşı,
/// prova izleyen biri) NV/QoD/AI sonuçlarını gerçek sanmasın.
class MockModeBanner extends StatelessWidget {
  const MockModeBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFB8860B), Color(0xFFD69E12)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: const Row(
        children: [
          Icon(Icons.science_outlined, size: 15, color: Colors.white),
          SizedBox(width: 7),
          Expanded(
            child: Text(
              'MOCK MOD — NV/QoD/backend/AI sonuçları simülasyon. Sadece stream ve kayıt gerçek.',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
