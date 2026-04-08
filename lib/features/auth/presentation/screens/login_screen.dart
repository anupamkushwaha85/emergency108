import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:emergency108_app/core/theme/app_theme.dart';
import 'package:emergency108_app/features/auth/data/auth_repository.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  String selectedRole = 'PUBLIC';
  final TextEditingController phoneController = TextEditingController();
  bool isPhoneValid = false;
  bool isLoading = false;
  int _otpCooldownSeconds = 0;
  Timer? _otpCooldownTimer;

  // FIX: compile the regex once at class level instead of on every keystroke.
  // RegExp is not a const constructor so we use static final.
  static final _phoneRegex = RegExp(r'^[6-9]\d{9}$');

  // FIX: pre-computed opaque equivalents of Colors.xxx.withOpacity(y).
  static const Color _roleSelectedBorder = Color(0x66000000); // black @ 40%
  static const Color _inputBackground    = Color(0xB3FFFFFF); // white @ 70%
  static const Color _inputBorder        = Color(0x33000000); // black @ 20%
  static const Color _countryCodeBg      = Color(0x1A000000); // black @ 10%

  @override
  void initState() {
    super.initState();
    phoneController.addListener(_validatePhone);
  }

  void _validatePhone() {
    final valid = _phoneRegex.hasMatch(phoneController.text);
    // FIX: only call setState when the value actually changes — avoids
    // rebuilding the whole screen on every keystroke when validity
    // hasn't flipped (e.g. typing the 2nd–9th digit).
    if (valid != isPhoneValid) setState(() => isPhoneValid = valid);
  }

  @override
  void dispose() {
    _otpCooldownTimer?.cancel();
    phoneController.removeListener(_validatePhone);
    phoneController.dispose();
    super.dispose();
  }

  void _startOtpCooldown([int seconds = 5]) {
    _otpCooldownTimer?.cancel();
    setState(() {
      _otpCooldownSeconds = seconds;
    });

    _otpCooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_otpCooldownSeconds <= 1) {
        timer.cancel();
        setState(() {
          _otpCooldownSeconds = 0;
        });
      } else {
        setState(() {
          _otpCooldownSeconds--;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Scaffold shrinks the body when keyboard appears so the back button
      // (at the bottom of the scroll) rises naturally above the keyboard.
      resizeToAvoidBottomInset: true,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: AppTheme.backgroundGradient,
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: Column(
              children: [
                const SizedBox(height: 60),
                // Title
                Text(
                  'Verify Your Phone Number',
                  style: GoogleFonts.poppins(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                    
                    const SizedBox(height: 50),
                    
                    // Select Your Role
                    Text(
                      'Select Your Role',
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    
                    const SizedBox(height: 12),
                    
                    // Role Toggle
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.black, width: 2),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  selectedRole = 'PUBLIC';
                                });
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                decoration: BoxDecoration(
                                  color: selectedRole == 'PUBLIC'
                                      ? const Color(0xFFFFB3B3)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(28),
                                  border: selectedRole == 'PUBLIC'
                                      ? Border.all(
                                          color: _roleSelectedBorder,
                                          width: 2,
                                        )
                                      : null,
                                ),
                                child: Transform.scale(
                                  scale: selectedRole == 'PUBLIC' ? 1.08 : 1.0,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.person,
                                        size: selectedRole == 'PUBLIC' ? 22 : 20,
                                        color: Colors.black87,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'PUBLIC',
                                        style: GoogleFonts.inter(
                                          fontSize: selectedRole == 'PUBLIC' ? 17 : 16,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.black87,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  selectedRole = 'DRIVER';
                                });
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                decoration: BoxDecoration(
                                  color: selectedRole == 'DRIVER'
                                      ? const Color(0xFFFFB3B3)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(28),
                                  border: selectedRole == 'DRIVER'
                                      ? Border.all(
                                          color: _roleSelectedBorder,
                                          width: 2,
                                        )
                                      : null,
                                ),
                                child: Transform.scale(
                                  scale: selectedRole == 'DRIVER' ? 1.08 : 1.0,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.local_shipping,
                                        size: selectedRole == 'DRIVER' ? 22 : 20,
                                        color: Colors.black87,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'DRIVER',
                                        style: GoogleFonts.inter(
                                          fontSize: selectedRole == 'DRIVER' ? 17 : 16,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.black87,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 40),
                    
                    // Mobile Number Label
                    Center(
                      child: Container(
                        width: 280,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Mobile Number',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 12),
                    
                    // Phone Number Input
                    Center(
                      child: Container(
                        width: 280, // Constrained width
                        decoration: BoxDecoration(
                          color: _inputBackground,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _inputBorder,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: _countryCodeBg,
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(8),
                                  bottomLeft: Radius.circular(8),
                                ),
                              ),
                              child: Text(
                                '+91',
                                style: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                            Expanded(
                              child: TextField(
                                controller: phoneController,
                                keyboardType: TextInputType.phone,
                                maxLength: 10,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                style: GoogleFonts.inter(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black87,
                                  letterSpacing: 1.5,
                                ),
                                decoration: InputDecoration(
                                  hintText: '9876543210',
                                  hintStyle: GoogleFonts.inter(
                                    color: Colors.black38,
                                  ),
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                  counterText: '',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 12),
                    
                    // Info Text
                    Text(
                      'OTP will be sent via SMS',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: Colors.black54,
                      ),
                    ),
                    Text(
                      'No charges apply',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: Colors.black54,
                      ),
                    ),
                    
                    const SizedBox(height: 40),
                    
                     // Send OTP Button
                    Opacity(
                      opacity: (isPhoneValid && !isLoading && _otpCooldownSeconds == 0) ? 1.0 : 0.5,
                      child: GestureDetector(
                        onTap: (isPhoneValid && !isLoading && _otpCooldownSeconds == 0) ? () async {
                          setState(() => isLoading = true);
                          try {
                            await ref.read(authRepositoryProvider).sendOtp(
                              phoneController.text,
                              selectedRole,
                            );

                            _startOtpCooldown();
                            
                            if (!mounted) return;
                            
                            // Navigate to OTP screen
                            context.push(
                              '/otp',
                              extra: {
                                'phone': phoneController.text,
                                'role': selectedRole,
                              },
                            );
                          } catch (e) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(e.toString()),
                                backgroundColor: Colors.red,
                              ),
                            );
                          } finally {
                            if (mounted) setState(() => isLoading = false);
                          }
                        } : null,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 50,
                            vertical: 14,
                          ),
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
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(color: Colors.black, width: 2),
                          ),
                          child: isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  _otpCooldownSeconds > 0
                                      ? 'Wait ${_otpCooldownSeconds}s'
                                      : 'Send OTP',
                                  style: GoogleFonts.inter(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
                    ),

                const SizedBox(height: 40),

                // Footer: description text (was Positioned bottom: 120)
                Text(
                  'This verification helps us dispatch help safely',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: Colors.black54,
                  ),
                ),
                if (selectedRole == 'DRIVER') ...[
                  const SizedBox(height: 8),
                  Text(
                    'Driver access is provided by admin',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Colors.black54,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                // Back Button (was Positioned bottom: 40)
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.arrow_back, color: Colors.black54, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Back',
                        style: GoogleFonts.inter(
                          color: Colors.black54,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
