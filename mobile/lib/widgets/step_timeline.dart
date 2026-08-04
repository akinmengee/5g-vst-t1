import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

const _stepLabels = ['Doğrula', 'Oturum', 'QoD', 'Kayıt', 'Yükle', 'AI', 'İz'];
const _dotDiameter = 26.0;

/// Open Gateway Demo UX Kılavuzu'ndaki "01 Doğrula → ... → 07 Trace" akışının
/// üst çubuktaki görsel karşılığı. [currentStep] (1-7) uygulamanın gerçek
/// durumundan ([SessionController.currentStepIndex]) besleniyor.
class StepTimeline extends StatelessWidget {
  final int currentStep;

  const StepTimeline({super.key, required this.currentStep});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppTheme.navy,
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
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
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
                          color: segmentDone
                              ? AppTheme.turkcellYellow
                              : Colors.white.withValues(alpha: 0.18),
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
        Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            shape: BoxShape.circle,
            border: isActive ? Border.all(color: Colors.white, width: 2) : null,
          ),
          child: Text(
            number.toString().padLeft(2, '0'),
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.bold,
              fontSize: 11,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: isDone || isActive ? AppTheme.turkcellYellow : Colors.white38,
            fontSize: 10,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }
}
