import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class GpaDataPoint {
  final String label;
  final double gpa;
  const GpaDataPoint(this.label, this.gpa);
}

class GpaLineChart extends StatelessWidget {
  final List<GpaDataPoint> data;
  final double height;

  const GpaLineChart({super.key, required this.data, this.height = 160});

  @override
  Widget build(BuildContext context) {
    if (data.length < 2) {
      return SizedBox(
        height: height,
        child: const Center(
          child: Text(
            'Add at least 2 completed semesters to see the chart',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: _GpaChartPainter(data),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _GpaChartPainter extends CustomPainter {
  final List<GpaDataPoint> data;
  _GpaChartPainter(this.data);

  static const green = AppTheme.green;
  static const _padL = 36.0;
  static const _padR = 12.0;
  static const _padT = 12.0;
  static const _padB = 40.0;

  @override
  void paint(Canvas canvas, Size size) {
    final n = data.length;
    final gpas = data.map((d) => d.gpa).toList();
    final minG = max(0.0, gpas.reduce(min) - 0.3);
    final maxG = min(4.0, gpas.reduce(max) + 0.3);
    final range = (maxG - minG).clamp(0.01, 4.0);

    final chartW = size.width - _padL - _padR;
    final chartH = size.height - _padT - _padB;

    double xOf(int i) => _padL + (n == 1 ? chartW / 2 : (i / (n - 1)) * chartW);
    double yOf(double g) => _padT + chartH - ((g - minG) / range) * chartH;

    // Grid lines
    final dashPaint = Paint()
      ..color = AppTheme.border2
      ..strokeWidth = 1;

    final labelStyle = const TextStyle(
      color: AppTheme.textMuted,
      fontSize: 9,
      fontWeight: FontWeight.w500,
    );

    for (final g in [1.0, 2.0, 3.0, 4.0]) {
      if (g < minG - 0.1 || g > maxG + 0.1) continue;
      final y = yOf(g);
      _drawDashedLine(canvas, dashPaint, Offset(_padL, y), Offset(size.width - _padR, y));
      _drawText(canvas, g.toStringAsFixed(1), Offset(0, y - 5), labelStyle, _padL - 4);
    }

    // Area fill
    final path = Path();
    path.moveTo(xOf(0), yOf(data[0].gpa));
    for (int i = 1; i < n; i++) {
      path.lineTo(xOf(i), yOf(data[i].gpa));
    }
    final fillPath = Path.from(path)
      ..lineTo(xOf(n - 1), size.height - _padB)
      ..lineTo(xOf(0), size.height - _padB)
      ..close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [green.withValues(alpha: 0.22), green.withValues(alpha: 0.0)],
      ).createShader(Rect.fromLTWH(_padL, _padT, chartW, chartH))
      ..style = PaintingStyle.fill;
    canvas.drawPath(fillPath, fillPaint);

    // Line
    final linePaint = Paint()
      ..color = green
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, linePaint);

    // Dots + labels
    final dotPaint = Paint()..color = green..style = PaintingStyle.fill;
    final dotBgPaint = Paint()..color = AppTheme.bg..style = PaintingStyle.fill;

    final valStyle = const TextStyle(
      color: AppTheme.green,
      fontSize: 9,
      fontWeight: FontWeight.w700,
    );
    final semStyle = const TextStyle(
      color: AppTheme.textMuted,
      fontSize: 9,
    );

    for (int i = 0; i < n; i++) {
      final x = xOf(i);
      final y = yOf(data[i].gpa);
      canvas.drawCircle(Offset(x, y), 5, dotBgPaint);
      canvas.drawCircle(Offset(x, y), 4, dotPaint);
      _drawText(canvas, data[i].gpa.toStringAsFixed(2), Offset(x, y - 16), valStyle, 40, centered: true);
      _drawText(canvas, data[i].label, Offset(x, size.height - _padB + 6), semStyle, 50, centered: true);
    }
  }

  void _drawDashedLine(Canvas canvas, Paint paint, Offset start, Offset end) {
    const dashLen = 3.0;
    const gapLen = 4.0;
    final total = (end - start).distance;
    final dir = (end - start) / total;
    double d = 0;
    while (d < total) {
      final s = start + dir * d;
      final e = start + dir * min(d + dashLen, total);
      canvas.drawLine(s, e, paint);
      d += dashLen + gapLen;
    }
  }

  void _drawText(Canvas canvas, String text, Offset origin, TextStyle style, double maxWidth, {bool centered = false}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
    final offset = centered
        ? Offset(origin.dx - tp.width / 2, origin.dy)
        : Offset(origin.dx - tp.width, origin.dy);
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(_GpaChartPainter old) => old.data != data;
}
