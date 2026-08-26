import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme.dart';

/// Recreation of the web `.ask-ai-button`: a slowly panning diagonal
/// gradient (green -> bright green -> violet -> green) plus a soft
/// rotating conic sheen, matching the `ask-ai-gradient` /
/// `ask-ai-rotate` keyframes from the CSS theme.
class GradientActionButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  const GradientActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon = Icons.face_retouching_natural,
  });

  @override
  State<GradientActionButton> createState() => _GradientActionButtonState();
}

class _GradientActionButtonState extends State<GradientActionButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value; // 0..1 loop
        return Opacity(
          opacity: enabled ? 1 : 0.5,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onPressed,
              borderRadius: BorderRadius.circular(14),
              child: Ink(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: LinearGradient(
                    begin: Alignment(-1 + 2 * t, -1),
                    end: Alignment(1 - 2 * t, 1),
                    colors: const [
                      AppColors.green,
                      AppColors.greenBright,
                      AppColors.violet,
                      AppColors.green,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.green.withValues(alpha: 0.18),
                      blurRadius: 20,
                      offset: const Offset(0, 7),
                    ),
                  ],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Rotating conic sheen clipped to the button shape.
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Transform.rotate(
                        angle: t * 2 * math.pi,
                        child: Container(
                          decoration: const BoxDecoration(
                            gradient: SweepGradient(
                              colors: [
                                Colors.transparent,
                                Color(0x52FFFFFF),
                                Colors.transparent,
                              ],
                              stops: [0.0, 0.28, 0.6],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(widget.icon, color: Colors.white, size: 20),
                          const SizedBox(width: 10),
                          Text(
                            widget.label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
