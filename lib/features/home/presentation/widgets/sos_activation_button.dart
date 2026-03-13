import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_theme.dart';

class SosActivationButton extends StatefulWidget {
  final VoidCallback onEmergencyTriggered;

  const SosActivationButton({
    super.key,
    required this.onEmergencyTriggered,
  });

  @override
  State<SosActivationButton> createState() => _SosActivationButtonState();
}

class _SosActivationButtonState extends State<SosActivationButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _holdController;

  @override
  void initState() {
    super.initState();
    _holdController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3), // 3s hold time
    );

    _holdController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onEmergencyTriggered();
        _holdController.reset();
      }
    });
  }

  @override
  void dispose() {
    _holdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Keep the interactive SOS circle exactly at screen center.
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 230,
                height: 230,
                child: AnimatedBuilder(
                  animation: _holdController,
                  builder: (context, child) {
                    return CircularProgressIndicator(
                      value: _holdController.value,
                      strokeWidth: 8,
                      valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryRed),
                      backgroundColor: AppTheme.primaryRed.withValues(alpha: 0.1),
                    );
                  },
                ),
              ),
              GestureDetector(
                onTapDown: (_) => _holdController.forward(),
                onTapUp: (_) {
                  if (_holdController.status != AnimationStatus.completed) {
                    _holdController.reverse();
                  }
                },
                onTapCancel: () => _holdController.reverse(),
                child: Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFFE6393C),
                        Color(0xFF990000),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'SOS',
                          style: GoogleFonts.inter(
                            fontSize: 48,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 2.0,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'HOLD 3s',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white70,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            bottom: 28,
            left: 24,
            right: 24,
            child: Text(
              'Press and hold for 3 seconds to alert emergency services',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: Colors.black54,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
