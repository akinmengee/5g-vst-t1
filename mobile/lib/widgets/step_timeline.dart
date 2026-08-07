import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

const _stepLabels = ['Doğrulama', 'Oturum', 'QoD', 'Kayıt', 'Yükle', 'AI Analizi', 'Trace'];
const _dotDiameter = 26.0;

/// Open Gateway Demo UX Kılavuzu'ndaki "01 Doğrula → ... → 07 Trace" akışının
/// üst çubuktaki görsel karşılığı. [currentStep] (1-7) uygulamanın gerçek
/// durumundan ([SessionController.currentStepIndex]) besleniyor. Adım
/// ilerledikçe çizgi ve noktalar animasyonla dolar.
class StepTimeline extends StatelessWidget {
  final int currentStep;

  const StepTimeline({super.key, required this.currentStep});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(gradient: AppTheme.headerGradient),
      child: DotMatrixBackground(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'DEMO AKIŞI',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 56,
                child: Stack(
                  alignment: Alignment.topCenter,
                  children: [
                    Positioned(
                      top: _dotDiameter / 2 - 1,
                      left: _dotDiameter / 2,
                      right: _dotDiameter / 2,
                      child: Row(
                        children: List.generate(_stepLabels.length - 1, (i) {
                          final segmentDone = (i + 2) <= currentStep;
                          return Expanded(
                            child: Container(
                              height: 2,
                              color: Colors.white.withValues(alpha: 0.18),
                              alignment: Alignment.centerLeft,
                              child: AnimatedFractionallySizedBox(
                                duration: const Duration(milliseconds: 450),
                                curve: Curves.easeOutCubic,
                                widthFactor: segmentDone ? 1.0 : 0.0,
                                child: Container(
                                  height: 2,
                                  color: AppTheme.turkcellYellow,
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                    Row(
                      children: List.generate(_stepLabels.length, (i) {
                        final stepNumber = i + 1;
                        return Expanded(
                          child: _StepDot(
                            number: stepNumber,
                            label: _stepLabels[i],
                            state: stepNumber < currentStep
                                ? _DotState.done
                                : stepNumber == currentStep
                                    ? _DotState.active
                                    : _DotState.upcoming,
                          ),
                        );
                      }),
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

enum _DotState { done, active, upcoming }

class _StepDot extends StatelessWidget {
  final int number;
  final String label;
  final _DotState state;

  const _StepDot({required this.number, required this.label, required this.state});

  @override
  Widget build(BuildContext context) {
    final isDone = state == _DotState.done;
    final isActive = state == _DotState.active;

    final bg = isDone || isActive ? AppTheme.turkcellYellow : Colors.white.withValues(alpha: 0.14);
    final fg = isDone || isActive ? AppTheme.navy : Colors.white54;
    final size = isActive ? _dotDiameter + 4 : _dotDiameter;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutBack,
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            shape: BoxShape.circle,
            border: isActive ? Border.all(color: Colors.white, width: 2) : null,
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: AppTheme.turkcellYellow.withValues(alpha: 0.45),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: isDone
              ? const Icon(Icons.check, size: 14, color: AppTheme.navy)
              : Text(
                  number.toString().padLeft(2, '0'),
                  style: TextStyle(
                    color: fg,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
        ),
        const SizedBox(height: 4),
        AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 250),
          style: TextStyle(
            color: isDone || isActive ? AppTheme.turkcellYellow : Colors.white38,
            fontSize: 10,
            fontFamily: 'Inter',
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
