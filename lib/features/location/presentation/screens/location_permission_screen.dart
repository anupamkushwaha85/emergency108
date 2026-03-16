import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:permission_handler/permission_handler.dart';
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
  int _currentStep = 0;
  static const int _totalSteps = 4;

  // Permission step definitions
  static const List<_PermissionStep> _steps = [
    _PermissionStep(
      icon: Icons.location_on_rounded,
      title: 'Location Access',
      subtitle: 'We need your location to send the\nnearest ambulance to you',
      isRequired: true,
    ),
    _PermissionStep(
      icon: Icons.notifications_active_rounded,
      title: 'Notifications',
      subtitle: 'Get real-time alerts about your\nemergency status and updates',
      isRequired: false,
    ),
    _PermissionStep(
      icon: Icons.contacts_rounded,
      title: 'Contacts',
      subtitle: 'Access contacts to quickly add\nemergency contact numbers',
      isRequired: false,
    ),
    _PermissionStep(
      icon: Icons.phone_in_talk_rounded,
      title: 'Phone Calls',
      subtitle: 'Auto-call your emergency contacts\nwhen you need help',
      isRequired: false,
    ),
  ];

  Future<void> _requestAllPermissions() async {
    setState(() => _isLoading = true);

    try {
      // ── Step 1: Location (REQUIRED) ──────────────────────────────────────
      setState(() => _currentStep = 0);

      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        await Geolocator.openLocationSettings();
        // Wait a moment for user to toggle GPS
        await Future.delayed(const Duration(milliseconds: 1200));
        serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location service is required to continue'),
              backgroundColor: Colors.red,
            ),
          );
          setState(() => _isLoading = false);
          return;
        }
      }

      LocationPermission locPerm = await Geolocator.checkPermission();
      if (locPerm == LocationPermission.denied) {
        locPerm = await Geolocator.requestPermission();
      }
      if (locPerm == LocationPermission.denied) {
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
      if (locPerm == LocationPermission.deniedForever) {
        await Geolocator.openAppSettings();
        if (!mounted) return;
        setState(() => _isLoading = false);
        return;
      }

      // ── Step 2: Notifications ──────────────────────────────────────────
      if (!mounted) return;
      setState(() => _currentStep = 1);
      await Future.delayed(const Duration(milliseconds: 300));
      await Permission.notification.request();

      // ── Step 3: Contacts ───────────────────────────────────────────────
      if (!mounted) return;
      setState(() => _currentStep = 2);
      await Future.delayed(const Duration(milliseconds: 300));
      await Permission.contacts.request();

      // ── Step 4: Phone ──────────────────────────────────────────────────
      if (!mounted) return;
      setState(() => _currentStep = 3);
      await Future.delayed(const Duration(milliseconds: 300));
      await Permission.phone.request();

      // ── All done → navigate ────────────────────────────────────────────
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
    final step = _steps[_currentStep.clamp(0, _steps.length - 1)];

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: AppTheme.backgroundGradient,
        ),
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 1),

              // ── Step indicator ────────────────────────────────────────
              if (_isLoading)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 60),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(_totalSteps, (i) {
                          final isActive = i <= _currentStep;
                          return Expanded(
                            child: Container(
                              height: 4,
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(2),
                                color: isActive
                                    ? const Color(0xFFE60D11)
                                    : const Color(0xFF333333).withOpacity(0.2),
                              ),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Step ${_currentStep + 1} of $_totalSteps',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: const Color(0xFF666666),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 20),

              // ── Title ─────────────────────────────────────────────────
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(
                  _isLoading ? step.title : 'App Permissions',
                  key: ValueKey(_isLoading ? step.title : 'initial'),
                  style: GoogleFonts.poppins(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF333333),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

              const SizedBox(height: 30),

              // ── Icon ──────────────────────────────────────────────────
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _isLoading
                    ? Container(
                        key: ValueKey(step.icon),
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFFE60D11).withOpacity(0.1),
                              const Color(0xFFE60D11).withOpacity(0.05),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: Icon(
                          step.icon,
                          size: 56,
                          color: const Color(0xFFE60D11),
                        ),
                      )
                    : SvgPicture.asset(
                        'assets/images/location_icon.svg',
                        key: const ValueKey('svg'),
                        width: 150,
                        height: 180,
                        fit: BoxFit.contain,
                      ),
              ),

              const SizedBox(height: 30),

              // ── Subtitle ──────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40.0),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(
                    _isLoading
                        ? step.subtitle
                        : 'We need a few permissions to\nkeep you safe during emergencies',
                    key: ValueKey(_isLoading ? step.subtitle : 'initial_sub'),
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF333333),
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),

              // ── Permission list (shown before requesting) ─────────────
              if (!_isLoading) ...[
                const SizedBox(height: 30),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Column(
                    children: _steps.map((s) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFFE60D11).withOpacity(0.1),
                              ),
                              child: Icon(s.icon, size: 18, color: const Color(0xFFE60D11)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                s.title,
                                style: GoogleFonts.inter(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF333333),
                                ),
                              ),
                            ),
                            if (s.isRequired)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE60D11).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'Required',
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFFE60D11),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],

              const Spacer(flex: 2),

              // ── Button ────────────────────────────────────────────────
              Center(
                child: GestureDetector(
                  onTap: _isLoading ? null : _requestAllPermissions,
                  child: Container(
                    width: 269,
                    height: 71,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFFF5E5E5),
                          Color(0xFFE60D11),
                          Color(0xFFC80000),
                          Color(0xFFE21F22),
                          Color(0xFFF5E5E5),
                        ],
                        stops: [0.0, 0.25, 0.5, 0.75, 1.0],
                      ),
                      borderRadius: BorderRadius.circular(43.5),
                      border: Border.all(color: Colors.black, width: 2),
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
                              'Allow Permissions',
                              style: GoogleFonts.inter(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // ── Privacy text ──────────────────────────────────────────
              Padding(
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
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissionStep {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isRequired;

  const _PermissionStep({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isRequired,
  });
}
