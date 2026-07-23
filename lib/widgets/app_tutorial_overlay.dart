import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/tutorial_service.dart';

/// Overlay tutoriel avec surbrillance sur les éléments ciblés.
class AppTutorialOverlay extends StatelessWidget {
  final List<TutorialStepData> steps;
  final int currentStep;
  final VoidCallback onNext;
  final VoidCallback onSkip;
  final Color primaryColor;

  const AppTutorialOverlay({
    super.key,
    required this.steps,
    required this.currentStep,
    required this.onNext,
    required this.onSkip,
    required this.primaryColor,
  });

  Rect? _targetRect(BuildContext context) {
    if (currentStep >= steps.length) return null;
    final key = steps[currentStep].targetKey;
    final renderBox = key.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return null;
    final offset = renderBox.localToGlobal(Offset.zero);
    return offset & renderBox.size;
  }

  @override
  Widget build(BuildContext context) {
    if (currentStep >= steps.length) return const SizedBox.shrink();

    final step = steps[currentStep];
    final target = _targetRect(context);
    final isLast = currentStep == steps.length - 1;
    final media = MediaQuery.of(context);

    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {}, // Bloque les interactions avec l'interface sous-jacente
        child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _HolePainter(
                hole: target,
                padding: 8,
              ),
            ),
          ),
          if (target != null)
            Positioned(
              left: target.left - 4,
              top: target.top - 4,
              width: target.width + 8,
              height: target.height + 8,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: primaryColor, width: 3),
                  ),
                ),
              ),
            ),
          Positioned(
            left: 20,
            right: 20,
            top: _tooltipTop(target, media.size.height),
            child: _TutorialCard(
              stepNumber: currentStep + 1,
              totalSteps: steps.length,
              title: step.title,
              description: step.description,
              isLast: isLast,
              primaryColor: primaryColor,
              onNext: onNext,
              onSkip: onSkip,
            ),
          ),
        ],
        ),
      ),
    );
  }

  double _tooltipTop(Rect? target, double screenHeight) {
    if (target == null) return screenHeight * 0.25;
    const cardHeight = 220.0;
    final below = target.bottom + 20;
    if (below + cardHeight < screenHeight - 40) return below;
    final above = target.top - cardHeight - 20;
    if (above > 80) return above;
    return screenHeight * 0.2;
  }
}

class _TutorialCard extends StatelessWidget {
  final int stepNumber;
  final int totalSteps;
  final String title;
  final String description;
  final bool isLast;
  final Color primaryColor;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  const _TutorialCard({
    required this.stepNumber,
    required this.totalSteps,
    required this.title,
    required this.description,
    required this.isLast,
    required this.primaryColor,
    required this.onNext,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Étape $stepNumber sur $totalSteps',
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: primaryColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: GoogleFonts.poppins(
              fontSize: 14,
              height: 1.45,
              color: isDark ? Colors.white70 : Colors.grey[700],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              TextButton(
                onPressed: onSkip,
                child: Text(
                  'Passer',
                  style: GoogleFonts.poppins(color: Colors.grey),
                ),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: onNext,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  isLast ? 'Terminer' : 'Suivant',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HolePainter extends CustomPainter {
  final Rect? hole;
  final double padding;

  _HolePainter({required this.hole, this.padding = 8});

  @override
  void paint(Canvas canvas, Size size) {
    final overlay = Paint()..color = Colors.black.withValues(alpha: 0.72);
    final full = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    if (hole != null) {
      final expanded = hole!.inflate(padding);
      final cut = Path()
        ..addRRect(RRect.fromRectAndRadius(expanded, const Radius.circular(14)));
      final path = Path.combine(PathOperation.difference, full, cut);
      canvas.drawPath(path, overlay);
    } else {
      canvas.drawPath(full, overlay);
    }
  }

  @override
  bool shouldRepaint(covariant _HolePainter oldDelegate) {
    return oldDelegate.hole != hole;
  }
}
