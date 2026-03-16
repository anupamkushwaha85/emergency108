import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:emergency108_app/core/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocationPermissionScreen extends ConsumerStatefulWidget {
  const LocationPermissionScreen({super.key});

  @override
  ConsumerState<LocationPermissionScreen> createState() =>
      _LocationPermissionScreenState();
}

class _LocationPermissionScreenState
    extends ConsumerState<LocationPermissionScreen> {
  bool _isLoading = false;

  Future<void> _requestLocationPermission() async {
    setState(() => _isLoading = true);

    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      
      if (!serviceEnabled) {
        // Try to open location settings
        await Geolocator.openLocationSettings();
        if (!mounted) return;
        setState(() => _isLoading = false);
        return;
      }

      // Check current permission status
      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        // Request permission
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        // Permission denied, show message
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location permission is required to continue'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isLoading = false);
        return;
      }

      if (permission == LocationPermission.deniedForever) {
        // Permissions are denied forever, open app settings
        await Geolocator.openAppSettings();
        if (!mounted) return;
        setState(() => _isLoading = false);
        return;
      }

      // Permission granted
      if (!mounted) return;
      
      final prefs = await SharedPreferences.getInstance();
      final role = prefs.getString('user_role');

      if (mounted) {
        if (role == 'DRIVER') {
           context.go('/driver-home');
        } else {
           context.go('/home');
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

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
            // Title Section - Centered at top similar to design
            Positioned(
              top: 100, // Adjusted to match relative visual weight
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  'Allow Location Access',
                  style: GoogleFonts.poppins(
                    fontSize: 24, // Matched Intro Screen Heading Size roughly
                    fontWeight: FontWeight.w700, // Bold as per design visual
                    color: const Color(0xFF333333),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),

            // Location SVG Icon - Centered
            Positioned(
              top: 150, // Adjusted based on visual flow
              left: 0,
              right: 0,
              child: Center(
                child: SvgPicture.asset(
                  'assets/images/location_icon.svg',
                  width: 150,
                  height: 180, // Approximate size from design context
                  fit: BoxFit.contain,
                ),
              ),
            ),

            // Description Text - Below Icon
            Positioned(
              top: 400, // Spaced below the icon
              left: 0,
              right: 0,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40.0),
                child: Text(
                  'We need your location to send the\nnearest ambulance to you',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w500, // Slightly bolder for readability
                    color: const Color(0xFF333333),
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),

            // Allow Location Button - Styled like "Get Started"
            Positioned(
              left: 0,
              right: 0,
              bottom: 240, 
              child: Center(
                child: GestureDetector(
                  onTap: _isLoading ? null : _requestLocationPermission,
                  child: Container(
                    width: 269, // Matches Intro Screen Button Width commonly used there if responsive, or specific request
                    height: 71, // Matches Intro Screen Button Height
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFFF5E5E5), // 0%
                          Color(0xFFE60D11), // 25%
                          Color(0xFFC80000), // 50%
                          Color(0xFFE21F22), // 75%
                          Color(0xFFF5E5E5), // 100%
                        ],
                        stops: [0.0, 0.25, 0.5, 0.75, 1.0],
                      ),
                      borderRadius: BorderRadius.circular(43.5),
                      border: Border.all(
                        color: Colors.black,
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.25),
                          blurRadius: 4,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Center(
                      child: _isLoading
                          ? const SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              'Allow Location',
                              style: GoogleFonts.inter( // Using Inter/Poppins consistent with design
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ),

            // Privacy Policy Text - Bottom
             Positioned(
              left: 0,
              right: 0,
              bottom: 80,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Colors.white,
                    ),
                    children: [
                      const TextSpan(text: 'By allowing you agree to our '),
                      TextSpan(
                        text: 'privacy policy',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline,
                          decorationColor: Colors.white,
                        ),
                      ),
                      const TextSpan(text: ' and\n'),
                      TextSpan(
                        text: 'terms & conditions',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline,
                          decorationColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
