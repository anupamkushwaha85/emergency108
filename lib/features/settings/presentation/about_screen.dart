import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_pallete.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('About Emergency 108'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFF1F1), Color(0xFFFFE5E5)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(color: const Color(0xFFFFD0D0)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: const BoxDecoration(
                      color: AppPallete.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.local_hospital_rounded, color: Colors.white, size: 30),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Emergency 108',
                          style: GoogleFonts.poppins(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF222222),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Fast emergency response and community support app',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: const Color(0xFF555555),
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _sectionTitle('What This App Does'),
            _paragraph(
              'Emergency 108 helps users raise SOS requests quickly, track ambulance dispatch in real time, and notify nearby community helpers through Helping Hand alerts.',
            ),
            const SizedBox(height: 14),
            _sectionTitle('Core Features'),
            _bullet('One-tap SOS creation with live tracking updates'),
            _bullet('Driver dispatch and mission status timeline'),
            _bullet('Helping Hand notifications for nearby responders'),
            _bullet('Emergency contacts and safety-first workflows'),
            const SizedBox(height: 14),
            _sectionTitle('Safety Note'),
            _paragraph(
              'This app assists emergency coordination, but it does not replace professional medical judgment. In critical situations, always follow local emergency authorities and medical professionals.',
            ),
            const SizedBox(height: 18),
            Text(
              'Version 1.0.0',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: const Color(0xFF888888),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: GoogleFonts.poppins(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: const Color(0xFF222222),
      ),
    );
  }

  Widget _paragraph(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        text,
        style: GoogleFonts.inter(
          fontSize: 14,
          color: const Color(0xFF4F4F4F),
          height: 1.55,
        ),
      ),
    );
  }

  Widget _bullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Icon(Icons.circle, size: 8, color: AppPallete.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: const Color(0xFF4F4F4F),
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
