import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/services/auth_session_service.dart';
import '../../../../core/theme/app_pallete.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;
  static const Duration _minimumSplashDuration = Duration(milliseconds: 800);

  // FIX: pre-computed opaque equivalents of AppPallete.error.withOpacity(x)
  // so AnimatedBuilder doesn't allocate new Color objects on every frame.
  static const Color _logoBackground = Color(0x1ACF6679); // error @ 10%
  static const Color _logoGlow      = Color(0x66CF6679); // error @ 40%

  @override
  void initState() {
    super.initState();
    
    // Animation Setup
    _controller = AnimationController(
       duration: const Duration(milliseconds: 1400),
       vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 0.5, end: 1.2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );

    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );

    _controller.forward();

    // Navigate after animation and check
    _checkAuthAndNavigate();
  }

  Future<void> _checkAuthAndNavigate() async {
    // Keep branding visible briefly, but avoid a fixed multi-second startup wait.
    final results = await Future.wait([
      Future.delayed(_minimumSplashDuration),
      SharedPreferences.getInstance(),
    ]);
    final prefs = results[1] as SharedPreferences;
    
    if (!mounted) return;

    final token = await AuthSessionService().readAuthToken();
    // Normalize role string to handle casing or whitespace issues
    final roleString = (prefs.getString('user_role') ?? 'PUBLIC').toUpperCase().trim();
    final isProfileComplete = prefs.getBool('is_profile_complete') ?? false;
    
    // FIX: debug prints only appear in debug builds
    if (kDebugMode) {
      debugPrint('==========================================');
      debugPrint('SPLASH DEBUG:');
      debugPrint('Token: $token');
      debugPrint('Raw Role: ${prefs.getString("user_role")}');
      debugPrint('Normalized Role: $roleString');
      debugPrint('Profile Complete: $isProfileComplete');
      debugPrint('==========================================');
    }

    if (token != null) {
      if (roleString == 'DRIVER') {
        // Driver -> check location, then Driver Dashboard
        final locationGranted = await _isLocationGranted();
        if (!mounted) return;
        context.go(locationGranted ? '/driver-home' : '/location-permission');
      } else {
        // User -> Check Profile
        if (!isProfileComplete) {
          // Force Profile Setup first — location check happens after profile
          context.go('/profile');
        } else {
          // Normal Home — gate on location permission
          final locationGranted = await _isLocationGranted();
          if (!mounted) return;
          context.go(locationGranted ? '/home' : '/location-permission');
        }
      }
    } else {
      // Not Logged In -> Show Intro (Get Started)
      context.go('/intro');
    }
  }

  /// Returns true only when location service is ON and permission is granted.
  /// Does NOT request permission — that's handled by LocationPermissionScreen.
  Future<bool> _isLocationGranted() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    final perm = await Geolocator.checkPermission();
    return perm == LocationPermission.whileInUse || perm == LocationPermission.always;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // Dark Theme bg
      body: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Opacity(
              opacity: _opacityAnimation.value,
              child: Transform.scale(
                scale: _scaleAnimation.value,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Logo Container
                    Container(
                      height: 120,
                      width: 120,
                      decoration: const BoxDecoration(
                        color: _logoBackground,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: _logoGlow,
                            blurRadius: 30,
                            spreadRadius: 10,
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.medical_services_rounded,
                          size: 60,
                          color: AppPallete.error,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Emergency 108',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Saving Lives, Faster.',
                      style: TextStyle(
                        color: AppPallete.grey,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
