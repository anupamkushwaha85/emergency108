import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Brand Colors (Figma Design)
  static const Color primaryRed = Color(0xFFFF2B2B); // Electric Red
  static const Color gradientStart = Color(0xFFFFEAEA); // Very light electric rose
  static const Color gradientEnd = Color(0xFFFFFFFF); // Pure White
  static const Color white = Colors.white;
  static const Color black = Colors.black;

  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFFFFD2D2), // 0% - Vibrant light electric rose
      Color(0xFFFFF2F2), // 40% - Soft transition
      Color(0xFFFFFFFF), // 100% - Pure White
    ],
    stops: [0.0, 0.4, 1.0],
  );

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: Colors.transparent, // Important for gradient background
      primaryColor: primaryRed,
      colorScheme: ColorScheme.light(
        primary: primaryRed,
        secondary: gradientEnd,
        surface: white,
        onPrimary: white,
        onSurface: black,
      ),

      // Smooth page transitions — use Cupertino (slide) for natural feel on all platforms
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      
      // Typography
      textTheme: TextTheme(
        displayLarge: GoogleFonts.poppins(
            fontSize: 28, fontWeight: FontWeight.bold, color: black),
        displayMedium: GoogleFonts.poppins(
            fontSize: 24, fontWeight: FontWeight.w600, color: black),
        bodyLarge: GoogleFonts.inter(
            fontSize: 16, fontWeight: FontWeight.normal, color: black),
        bodyMedium: GoogleFonts.inter(
            fontSize: 14, fontWeight: FontWeight.normal, color: Colors.black87),
        labelLarge: GoogleFonts.inter( // Button text
            fontSize: 16, fontWeight: FontWeight.bold, color: white),
      ),

      // Button Theme
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryRed,
          foregroundColor: white,
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          elevation: 5,
        ),
      ),
    );
  }
}
