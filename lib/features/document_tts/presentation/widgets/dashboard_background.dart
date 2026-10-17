import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Decorative background layer with rich lavender/mint gradient washes
/// and sparse, high-fidelity vector outlines of books, headphones, documents, and waveforms.
///
/// Wrapped in [IgnorePointer] and [ExcludeSemantics] so it ignores all touch
/// events and accessibility focus.
class DashboardBackground extends StatelessWidget {
  const DashboardBackground({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return IgnorePointer(
      ignoring: true,
      child: ExcludeSemantics(
        excluding: true,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Base Gradient Background (Soft off-white canvas with subtle ambient diagonal wash)
            Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0B1120) : const Color(0xFFFAF9FF),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? const [
                          Color(0xFF0F172A),
                          Color(0xFF13192E),
                          Color(0xFF0C1724),
                        ]
                      : const [
                          Color(0xFFFAF9FF),
                          Color(0xFFF6F8FD),
                          Color(0xFFF2FBF9),
                        ],
                ),
              ),
            ),

            // 2. Rich Soft Lavender Wash (Top-Left extending down left margin)
            Positioned(
              top: -80,
              left: -70,
              width: 380,
              height: 420,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    center: const Alignment(-0.2, -0.2),
                    radius: 0.85,
                    colors: isDark
                        ? [
                            const Color(0xFF4C1D95).withValues(alpha: 0.45),
                            const Color(0xFF2E1065).withValues(alpha: 0.20),
                            Colors.transparent,
                          ]
                        : [
                            const Color(0xFFDDD6FE).withValues(alpha: 0.85),
                            const Color(0xFFEDE9FE).withValues(alpha: 0.50),
                            Colors.transparent,
                          ],
                    stops: const [0.0, 0.55, 1.0],
                  ),
                ),
              ),
            ),

            // 3. Rich Gentle Mint Wash (Top-Right extending down right margin)
            Positioned(
              top: -60,
              right: -70,
              width: 380,
              height: 400,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    center: const Alignment(0.2, -0.2),
                    radius: 0.85,
                    colors: isDark
                        ? [
                            const Color(0xFF065F46).withValues(alpha: 0.40),
                            const Color(0xFF134E4A).withValues(alpha: 0.18),
                            Colors.transparent,
                          ]
                        : [
                            const Color(0xFF99F6E4).withValues(alpha: 0.80),
                            const Color(0xFFCCFBF1).withValues(alpha: 0.45),
                            Colors.transparent,
                          ],
                    stops: const [0.0, 0.55, 1.0],
                  ),
                ),
              ),
            ),

            // 4. Mid-Right Turquoise/Mint Wash (Beside Choose Feature & Recent Documents)
            Positioned(
              top: 320,
              right: -80,
              width: 300,
              height: 380,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    center: const Alignment(0.1, 0.0),
                    radius: 0.85,
                    colors: isDark
                        ? [
                            const Color(0xFF0F766E).withValues(alpha: 0.32),
                            const Color(0xFF134E4A).withValues(alpha: 0.12),
                            Colors.transparent,
                          ]
                        : [
                            const Color(0xFFA7F3D0).withValues(alpha: 0.70),
                            const Color(0xFFD1FAE5).withValues(alpha: 0.35),
                            Colors.transparent,
                          ],
                    stops: const [0.0, 0.55, 1.0],
                  ),
                ),
              ),
            ),

            // 5. Mid-to-Lower Left Lavender Wash (Beside Choose Feature & Recent Documents)
            Positioned(
              top: 380,
              left: -80,
              width: 290,
              height: 380,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    center: const Alignment(-0.1, 0.0),
                    radius: 0.85,
                    colors: isDark
                        ? [
                            const Color(0xFF3B1D6B).withValues(alpha: 0.35),
                            const Color(0xFF2E1065).withValues(alpha: 0.15),
                            Colors.transparent,
                          ]
                        : [
                            const Color(0xFFE9D5FF).withValues(alpha: 0.70),
                            const Color(0xFFF3E8FF).withValues(alpha: 0.35),
                            Colors.transparent,
                          ],
                    stops: const [0.0, 0.55, 1.0],
                  ),
                ),
              ),
            ),

            // 6. Sparse, High-Contrast Decorative Outlines (Canvas)
            CustomPaint(
              painter: _DashboardDecorativePainter(isDark: isDark),
              size: Size.infinite,
            ),
          ],
        ),
      ),
    );
  }
}

/// Paints prominent, high-fidelity outline motifs (books, headphones, documents, waveforms)
/// positioned in visible exposed margins and section gaps, keeping well away from headings and text.
class _DashboardDecorativePainter extends CustomPainter {
  final bool isDark;

  _DashboardDecorativePainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    // 16-18% opacity for crisp visibility matching the mockup
    final lavenderPaint = Paint()
      ..color = isDark
          ? const Color(0xFFA78BFA).withValues(alpha: 0.18)
          : const Color(0xFF7C3AED).withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final mintPaint = Paint()
      ..color = isDark
          ? const Color(0xFF2DD4BF).withValues(alpha: 0.18)
          : const Color(0xFF0D9488).withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final docPaint = Paint()
      ..color = isDark
          ? const Color(0xFF94A3B8).withValues(alpha: 0.16)
          : const Color(0xFF6366F1).withValues(alpha: 0.17)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // -------------------------------------------------------------
    // TOP REGION (Exposed margins above & around Workspace Overview)
    // -------------------------------------------------------------

    // 1. TOP-RIGHT: Folded Document Sheet Outline (near top status/app bar right)
    _drawDocumentSheet(
      canvas,
      x: size.width - 65,
      y: 18,
      width: 38,
      height: 48,
      angle: 0.14,
      paint: docPaint,
    );

    // 2. TOP-RIGHT: Open Book Outline (Visible in upper right margin above carousel)
    // Size increased to 76x50, perfectly positioned in the exposed corner
    _drawOpenBook(
      canvas,
      x: size.width - 92,
      y: 62,
      width: 76,
      height: 48,
      angle: -0.12,
      paint: lavenderPaint,
    );

    // 3. UPPER-RIGHT EDGE: Audio Waveform Bars (Beside Workspace Overview card)
    _drawWaveform(
      canvas,
      x: size.width - 13,
      y: 130,
      barHeights: const [8, 22, 34, 18, 26, 12],
      spacing: 3.5,
      paint: mintPaint,
    );

    // 4. UPPER-LEFT EDGE: Audio Waveform Bars (Beside Workspace Overview card)
    _drawWaveform(
      canvas,
      x: 8,
      y: 200,
      barHeights: const [10, 20, 30, 16, 24],
      spacing: 3.5,
      paint: mintPaint,
    );

    // -------------------------------------------------------------
    // MID REGION (Exposed margins & gaps around Choose Feature)
    // -------------------------------------------------------------

    // 5. MID-LEFT MARGIN: Folded Document Sheet Outline (Beside Choose Feature heading)
    _drawDocumentSheet(
      canvas,
      x: 8,
      y: 310,
      width: 38,
      height: 50,
      angle: 0.18,
      paint: docPaint,
    );

    // 6. PROMINENT HEADPHONES OUTLINE (Right margin beside Speech to Text card)
    // In the mockup, this is large (~62x68) and clearly visible in the right margin/gap
    _drawHeadphones(
      canvas,
      centerX: size.width - 32,
      centerY: 395,
      radius: 26,
      paint: lavenderPaint,
    );

    // 7. MID-RIGHT EDGE: Audio Waveform Bars (Below headphones)
    _drawWaveform(
      canvas,
      x: size.width - 13,
      y: 320,
      barHeights: const [8, 16, 26, 14, 20],
      spacing: 3.5,
      paint: mintPaint,
    );

    // -------------------------------------------------------------
    // LOWER REGION (Exposed margins around Recent Extracted Documents)
    // -------------------------------------------------------------

    // 8. LOWER-LEFT MARGIN: Folded Document Sheet (Beside Recent Documents card)
    _drawDocumentSheet(
      canvas,
      x: 8,
      y: 660,
      width: 36,
      height: 48,
      angle: -0.12,
      paint: docPaint,
    );

    // 9. LOWER-RIGHT MARGIN: Audio Waveform Bars (Beside Recent Documents card)
    _drawWaveform(
      canvas,
      x: size.width - 13,
      y: 670,
      barHeights: const [10, 22, 32, 16, 24, 12],
      spacing: 3.5,
      paint: mintPaint,
    );
  }

  void _drawDocumentSheet(
    Canvas canvas, {
    required double x,
    required double y,
    required double width,
    required double height,
    required double angle,
    required Paint paint,
  }) {
    canvas.save();
    canvas.translate(x + width / 2, y + height / 2);
    canvas.rotate(angle);
    canvas.translate(-width / 2, -height / 2);

    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, width, height),
      const Radius.circular(6),
    );
    canvas.drawRRect(rect, paint);

    // Folded top-right corner indicator
    final foldSize = width * 0.30;
    final foldPath = Path()
      ..moveTo(width - foldSize, 0)
      ..lineTo(width, foldSize);
    canvas.drawPath(foldPath, paint);

    // Internal text lines
    final linePaint = Paint()
      ..color = paint.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round;

    final lineMargin = width * 0.20;
    final startY = height * 0.36;
    final lineSpacing = height * 0.16;

    for (int i = 0; i < 3; i++) {
      final currentY = startY + (i * lineSpacing);
      final lineW = (i == 2) ? width * 0.38 : width * 0.58;
      canvas.drawLine(
        Offset(lineMargin, currentY),
        Offset(lineMargin + lineW, currentY),
        linePaint,
      );
    }

    canvas.restore();
  }

  void _drawOpenBook(
    Canvas canvas, {
    required double x,
    required double y,
    required double width,
    required double height,
    required double angle,
    required Paint paint,
  }) {
    canvas.save();
    canvas.translate(x + width / 2, y + height / 2);
    canvas.rotate(angle);
    canvas.translate(-width / 2, -height / 2);

    final pageW = width / 2;
    const spineGap = 1.0;

    // Left Page curved path
    final leftPath = Path();
    leftPath.moveTo(pageW - spineGap, 4);
    leftPath.quadraticBezierTo(pageW * 0.5, 0, 0, 4);
    leftPath.lineTo(0, height - 4);
    leftPath.quadraticBezierTo(pageW * 0.5, height - 8, pageW - spineGap, height);
    leftPath.close();
    canvas.drawPath(leftPath, paint);

    // Right Page curved path
    final rightPath = Path();
    rightPath.moveTo(pageW + spineGap, 4);
    rightPath.quadraticBezierTo(pageW + pageW * 0.5, 0, width, 4);
    rightPath.lineTo(width, height - 4);
    rightPath.quadraticBezierTo(pageW + pageW * 0.5, height - 8, pageW + spineGap, height);
    rightPath.close();
    canvas.drawPath(rightPath, paint);

    // Center Spine Line
    canvas.drawLine(
      Offset(pageW, 2),
      Offset(pageW, height),
      paint,
    );

    // Subtle page text lines
    final innerPaint = Paint()
      ..color = paint.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round;

    // Left page lines
    canvas.drawLine(Offset(pageW * 0.22, height * 0.35), Offset(pageW * 0.78, height * 0.33), innerPaint);
    canvas.drawLine(Offset(pageW * 0.22, height * 0.55), Offset(pageW * 0.78, height * 0.53), innerPaint);

    // Right page lines
    canvas.drawLine(Offset(pageW + pageW * 0.22, height * 0.33), Offset(pageW + pageW * 0.78, height * 0.35), innerPaint);
    canvas.drawLine(Offset(pageW + pageW * 0.22, height * 0.53), Offset(pageW + pageW * 0.78, height * 0.55), innerPaint);

    canvas.restore();
  }

  void _drawHeadphones(
    Canvas canvas, {
    required double centerX,
    required double centerY,
    required double radius,
    required Paint paint,
  }) {
    canvas.save();
    canvas.translate(centerX, centerY);
    canvas.rotate(0.12);

    // Headband arc
    final arcRect = Rect.fromCircle(center: Offset.zero, radius: radius);
    canvas.drawArc(
      arcRect,
      math.pi,
      math.pi,
      false,
      paint,
    );

    // Left and Right earcup positions
    final cupW = radius * 0.42;
    final cupH = radius * 0.82;

    // Left Earcup
    final leftCup = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(-radius + 2, cupH * 0.28),
        width: cupW,
        height: cupH,
      ),
      const Radius.circular(6),
    );
    canvas.drawRRect(leftCup, paint);

    // Right Earcup
    final rightCup = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(radius - 2, cupH * 0.28),
        width: cupW,
        height: cupH,
      ),
      const Radius.circular(6),
    );
    canvas.drawRRect(rightCup, paint);

    // Inner earcup cushions
    final cushionPaint = Paint()
      ..color = paint.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(-radius + cupW * 0.5, 0),
      Offset(-radius + cupW * 0.5, cupH * 0.5),
      cushionPaint,
    );
    canvas.drawLine(
      Offset(radius - cupW * 0.5, 0),
      Offset(radius - cupW * 0.5, cupH * 0.5),
      cushionPaint,
    );

    canvas.restore();
  }

  void _drawWaveform(
    Canvas canvas, {
    required double x,
    required double y,
    required List<double> barHeights,
    required double spacing,
    required Paint paint,
  }) {
    final barPaint = Paint()
      ..color = paint.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < barHeights.length; i++) {
      final h = barHeights[i];
      final currentX = x + (i * spacing);
      canvas.drawLine(
        Offset(currentX, y - (h / 2)),
        Offset(currentX, y + (h / 2)),
        barPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DashboardDecorativePainter oldDelegate) {
    return oldDelegate.isDark != isDark;
  }
}
