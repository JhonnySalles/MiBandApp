import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class StepGauge extends StatelessWidget {
  final int steps;
  final int goal;
  final int calories;
  final double distanceKm;

  const StepGauge({
    super.key,
    required this.steps,
    required this.goal,
    required this.calories,
    required this.distanceKm,
  });

  @override
  Widget build(BuildContext context) {
    final progress = (goal > 0 ? (steps / goal) : 0.0).clamp(0.0, 1.0);
    final percentage = (progress * 100).toInt();

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          SizedBox(
            width: 220,
            height: 220,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(220, 220),
                  painter: _GaugePainter(progress: progress),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.directions_walk_rounded, color: AppTheme.primaryOrange, size: 28),
                    const SizedBox(height: 4),
                    Text(
                      steps.toString(),
                      style: const TextStyle(
                        fontSize: 38,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.textPrimary,
                        letterSpacing: -1,
                      ),
                    ),
                    Text(
                      "Meta: $goal passos ($percentage%)",
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildSubMetric(
                icon: Icons.local_fire_department_rounded,
                color: const Color(0xFFFF5252),
                title: "Calorias",
                value: "$calories",
                unit: "kcal",
              ),
              Container(width: 1, height: 36, color: AppTheme.cardSubtle),
              _buildSubMetric(
                icon: Icons.place_rounded,
                color: AppTheme.healthCyan,
                title: "Distância",
                value: distanceKm.toStringAsFixed(2),
                unit: "km",
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSubMetric({
    required IconData icon,
    required Color color,
    required String title,
    required String value,
    required String unit,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(width: 3),
                Text(
                  unit,
                  style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double progress;

  _GaugePainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 14;

    // Fundo do arco
    final bgPaint = Paint()
      ..color = AppTheme.cardSubtle
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, bgPaint);

    // Arco de progresso com gradiente
    final sweepAngle = 2 * pi * progress;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final gradient = const SweepGradient(
      startAngle: 0.0,
      endAngle: 2 * pi,
      colors: [AppTheme.primaryOrange, AppTheme.accentOrange, Color(0xFFFF9E40), AppTheme.primaryOrange],
      transform: GradientRotation(-pi / 2),
    );

    final progressPaint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      rect,
      -pi / 2, // Inicia no topo (12 horas)
      sweepAngle,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) => oldDelegate.progress != progress;
}
