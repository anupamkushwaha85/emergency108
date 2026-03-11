import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:emergency108_app/core/theme/app_theme.dart';
import 'package:emergency108_app/features/auth/presentation/screens/login_screen.dart';

class IntroScreen extends StatefulWidget {
  const IntroScreen({Key? key}) : super(key: key);

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> {
  String selectedLanguage = 'EN';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: AppTheme.backgroundGradient,
        ),
        child: Stack(
          children: [
            // Language Selector (Top Right)
            Positioned(
              top: 50,
              right: 24,
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    selectedLanguage = selectedLanguage == 'EN' ? 'हिंदी' : 'EN';
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.black.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        selectedLanguage == 'EN' ? 'EN' : 'हिंदी',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.keyboard_arrow_down,
                        size: 18,
                        color: Colors.black87,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            
            // Ambulance Animation
            Positioned(
              top: 100,
              left: 0,
              right: 0,
              child: Center(
                child: SizedBox(
                  width: 200,
                  height: 200,
                  child: Lottie.asset(
                    'assets/icons/ambulancia.json',
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
            
            // Main Heading
            Positioned(
              top: 320,
              left: 0,
              right: 0,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32.0),
                  child: Text(
                    selectedLanguage == 'EN' 
                        ? 'Help Is Just One Tap Away'
                        : 'मदद बस एक टैप दूर है',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      color: Colors.black,
                      height: 1.2,
                    ),
                  ),
                ),
              ),
            ),
            
            // Description Text
            Positioned(
              top: 400,
              left: 0,
              right: 0,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32.0),
                  child: Text(
                    selectedLanguage == 'EN'
                        ? 'Emergency help will be dispatched\nimmediately to your location'
                        : 'आपातकालीन सहायता तुरंत आपके\nस्थान पर भेजी जाएगी',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.normal,
                      color: Colors.black87,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
            ),
            
            // Live Tracking Row
            Positioned(
              top: 475,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.sensors,
                    size: 20,
                    color: Colors.black87,
                  ),
                  SizedBox(width: 8),
                  Text(
                    selectedLanguage == 'EN' ? 'Live tracking' : 'लाइव ट्रैकिंग',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            

            // Get Started Button - positioned above bottom text
            Positioned(
              left: 0,
              right: 0,
              bottom: 220, // Higher up for thumb accessibility
              child: Center(
                child: Container(
                  width: 229,
                  height: 71,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFFF5E5E5), // 0% - Lighter white/pink (top-left highlight)
                        Color(0xFFE60D11), // 25% - Deep red
                        Color(0xFFC80000), // 50% - Darker red center
                        Color(0xFFE21F22), // 75% - Red
                        Color(0xFFF5E5E5), // 100% - Lighter white/pink (bottom-right highlight)
                      ],
                      stops: [0.0, 0.25, 0.5, 0.75, 1.0],
                    ),
                    borderRadius: BorderRadius.circular(43.5),
                    border: Border.all(
                      color: Colors.black,
                      width: 2,
                    ),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        Navigator.of(context).push(
                          PageRouteBuilder(
                            pageBuilder: (context, animation, secondaryAnimation) {
                              return const LoginScreen();
                            },
                            transitionsBuilder: (context, animation, secondaryAnimation, child) {
                              const begin = Offset(1.0, 0.0); // Start from right
                              const end = Offset.zero;
                              const curve = Curves.easeIn;

                              var tween = Tween(begin: begin, end: end).chain(
                                CurveTween(curve: curve),
                              );

                              return SlideTransition(
                                position: animation.drive(tween),
                                child: child,
                              );
                            },
                            transitionDuration: const Duration(milliseconds: 300),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(43.5),
                      child: Center(
                        child: Text(
                          selectedLanguage == 'EN' ? 'Get Started' : 'शुरू करें',
                          style: GoogleFonts.inter(
                            fontSize: 26, 
                            fontWeight: FontWeight.w700, 
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            
            // Text positioned near bottom, responsive to screen size
            Positioned(
              left: 0,
              right: 0,
              bottom: 60,
              child: Center(
                child: Text(
                  selectedLanguage == 'EN'
                      ? "Designed for India's 108 Emergency Response"
                      : "भारत की 108 आपातकालीन सेवा के लिए डिज़ाइन किया गया",
                  style: GoogleFonts.inter(
                    fontSize: 14, // Reduced from 18 to fit in one line
                    fontWeight: FontWeight.w400,
                    color: const Color(0xFFFFFFFF),
                    height: 1.0,
                    letterSpacing: 0,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
