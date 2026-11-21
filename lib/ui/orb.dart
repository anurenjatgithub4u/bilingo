import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Glowing blue orb that gently pulses.
class Orb extends StatefulWidget {
  const Orb({super.key, this.size = 150});

  final double size;

  @override
  State<Orb> createState() => _OrbState();
}

class _OrbState extends State<Orb> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(_c.value);
        final size = widget.size * (1 + 0.05 * t);
        return SizedBox(
          width: widget.size * 1.1,
          height: widget.size * 1.1,
          child: Center(
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(
                  center: Alignment(-0.3, -0.4),
                  radius: 0.95,
                  colors: [Color(0xFFBFE0FF), kBrandBlue, Color(0xFF1B4FD8)],
                  stops: [0.0, 0.55, 1.0],
                ),
                boxShadow: [
                  BoxShadow(
                    color: kBrandBlue.withValues(alpha: 0.30 + 0.2 * t),
                    blurRadius: 40 + 20 * t,
                    spreadRadius: 4,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
