import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_theme.dart';

class EmergencyCountdownView extends StatelessWidget {
  // FIX: accept a ValueNotifier instead of a plain int so only the Text widget
  // rebuilds every second — not the entire HomeScreen tree.
  final ValueNotifier<int> countdownNotifier;
  final VoidCallback onManualDispatch;

  // Pre-computed opaque equivalents of primaryRed.withOpacity(x)
  // Avoids allocating a new Color object on every build call.
  static const Color _borderColor = Color(0x4DFF2B2B);  // 0.30 opacity
  static const Color _shadowColor = Color(0x26FF2B2B);  // 0.15 opacity

  const EmergencyCountdownView({
    super.key,
    required this.countdownNotifier,
    required this.onManualDispatch,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(30),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            border: Border.fromBorderSide(
              BorderSide(color: _borderColor, width: 3),
            ),
            color: AppTheme.white,
            boxShadow: [
              BoxShadow(
                color: _shadowColor,
                blurRadius: 20,
                offset: Offset(0, 5),
              ),
            ],
          ),
          // Only this Text rebuilds every second — not the whole screen.
          child: ValueListenableBuilder<int>(
            valueListenable: countdownNotifier,
            builder: (_, value, __) => Text(
              '$value',
              style: GoogleFonts.inter(
                fontSize: 60,
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryRed,
                height: 1.0,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'seconds until auto-dispatch',
          style: GoogleFonts.inter(
            color: Colors.black54,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 40),
        GestureDetector(
          onTap: onManualDispatch,
          child: Text(
            'Skip Wait: Dispatch Now',
            style: GoogleFonts.inter(
              color: AppTheme.primaryRed,
              fontWeight: FontWeight.w700,
              fontSize: 16,
              decoration: TextDecoration.underline,
              decorationColor: AppTheme.primaryRed,
            ),
          ),
        ),
      ],
    );
  }
}
