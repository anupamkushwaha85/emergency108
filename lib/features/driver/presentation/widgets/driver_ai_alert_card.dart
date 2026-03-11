import 'package:flutter/material.dart';
import '../../../../core/theme/app_pallete.dart';

class DriverAiAlertCard extends StatelessWidget {
  final String? aiAssessment;

  const DriverAiAlertCard({super.key, this.aiAssessment});

  @override
  Widget build(BuildContext context) {
    if (aiAssessment == null || aiAssessment!.isEmpty) {
      return const SizedBox.shrink();
    }

    // Determine severity based on keywords (Mock logic)
    // Real logic would parse the JSON assessment object
    bool isCritical = aiAssessment!.contains("Unconscious") || 
                      aiAssessment!.contains("Bleeding") || 
                      aiAssessment!.contains("Critical");

    Color cardColor = isCritical ? AppPallete.error : Colors.orange;

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor.withOpacity(0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cardColor, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
               Icon(Icons.medical_services_outlined, color: cardColor, size: 28),
               const SizedBox(width: 12),
               Text(
                 "MEDICAL ALERT",
                 style: TextStyle(
                   color: cardColor,
                   fontWeight: FontWeight.bold,
                   fontSize: 16,
                   letterSpacing: 1.1,
                 ),
               ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            aiAssessment!,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
             "AI Analysis • Verify upon arrival",
             style: TextStyle(color: cardColor.withOpacity(0.8), fontSize: 12),
          ),
        ],
      ),
    );
  }
}
