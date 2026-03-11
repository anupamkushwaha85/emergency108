import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:emergency108_app/core/theme/app_theme.dart';
import 'package:sms_autofill/sms_autofill.dart';
import 'package:emergency108_app/features/auth/data/auth_repository.dart';
import 'package:emergency108_app/core/services/fcm_notification_service.dart';
import 'package:emergency108_app/features/profile/presentation/screens/profile_screen.dart';

class OtpScreen extends ConsumerStatefulWidget {
  final String phone;
  final String role;

  const OtpScreen({
    super.key,
    required this.phone,
    required this.role,
  });

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final List<TextEditingController> _otpControllers = List.generate(
    6,
    (index) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(6, (index) => FocusNode());

  // FIX: Use ValueNotifier for the countdown so ONLY the timer text widget
  // rebuilds every second — not the entire OTP screen with all 6 TextFields.
  final ValueNotifier<int> _timerNotifier = ValueNotifier(60);
  final ValueNotifier<bool> _canResendNotifier = ValueNotifier(false);

  Timer? _timer;
  bool _isOtpComplete = false;
  bool _isVerifying = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
    for (var controller in _otpControllers) {
      controller.addListener(_checkOtpComplete);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNodes[0].requestFocus();
    });
    _listenForSmsCode();
  }

  void _listenForSmsCode() async {
    try {
      await SmsAutoFill().listenForCode();
      // Signature only needed during development/testing
      assert(() {
        SmsAutoFill().getAppSignature.then((sig) => debugPrint('App Signature: $sig'));
        return true;
      }());
    } catch (e) {
      debugPrint('SMS Autofill Error: $e');
    }
  }

  // FIX: Guard setState — only call it when _isOtpComplete actually changes.
  // Previously setState was called unconditionally on every keystroke across
  // all 6 boxes, rebuilding the entire screen even when nothing changed.
  void _checkOtpComplete() {
    final complete = _otpControllers.every((c) => c.text.isNotEmpty);
    if (complete != _isOtpComplete) {
      setState(() => _isOtpComplete = complete);
    }
  }

  // FIX: Timer now updates ValueNotifiers instead of calling setState.
  // Only the two small ValueListenableBuilder widgets rebuild — not the
  // whole screen with 6 TextFields, gradients, and all text every second.
  void _startTimer() {
    _timer?.cancel();
    _timerNotifier.value = 60;
    _canResendNotifier.value = false;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_timerNotifier.value == 0) {
        timer.cancel();
        _canResendNotifier.value = true;
      } else {
        _timerNotifier.value--;
      }
    });
  }

  @override
  void dispose() {
    for (var controller in _otpControllers) {
      controller.dispose();
    }
    for (var node in _focusNodes) {
      node.dispose();
    }
    _timer?.cancel();
    _timerNotifier.dispose();
    _canResendNotifier.dispose();
    SmsAutoFill().unregisterListener();
    super.dispose();
  }

  void _resendOtp() async {
    if (_isVerifying) return;
    setState(() => _isOtpComplete = false);
    // Clear all boxes
    for (var c in _otpControllers) {
      c.clear();
    }
    _focusNodes[0].requestFocus();
    try {
      await ref.read(authRepositoryProvider).sendOtp(widget.phone, widget.role);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('OTP has been resent!'),
          backgroundColor: Colors.green,
        ),
      );

      _startTimer();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _verifyOtp() async {
    final otp = _otpControllers.map((c) => c.text).join();
    if (otp.length != 6) return;
    if (_isVerifying) return;

    setState(() => _isVerifying = true);

    try {
      final token = await ref.read(authRepositoryProvider).verifyOtp(
        widget.phone,
        otp,
      );

      debugPrint('Token received: ${token.substring(0, 10)}...');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('OTP Verified Successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      // Register FCM token for push notifications (non-blocking)
      unawaited(() async {
        try {
          final fcmService = FCMNotificationService();
          final fcmToken = await fcmService.initialize();
          if (fcmToken != null) {
            await ref.read(authRepositoryProvider).registerFcmToken(fcmToken);
            fcmService.setupForegroundHandler();
            fcmService.setupNotificationTapHandler((data) {
              debugPrint('Notification tapped with data: $data');
            });
          }
        } catch (e) {
          debugPrint('FCM registration failed (non-critical): $e');
        }
      }());

      // Check profile completion status
      final prefs = await SharedPreferences.getInstance();
      final isProfileComplete = prefs.getBool('is_profile_complete') ?? false;

      if (!mounted) return;

      if (isProfileComplete) {
        if (widget.role == 'DRIVER') {
          context.go('/driver-home');
        } else {
          context.go('/home');
        }
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => const ProfileScreen(),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  String _getMaskedPhone() {
    if (widget.phone.length >= 10) {
      final first2 = widget.phone.substring(0, 2);
      final last4 = widget.phone.substring(widget.phone.length - 4);
      return '+91 $first2****$last4';
    }
    return '+91 ${widget.phone}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                  'Verify OTP',
                  style: GoogleFonts.poppins(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),

                    const SizedBox(height: 40),

                    // OTP sent to text
                    Text(
                      'OTP sent to ${_getMaskedPhone()}',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: Colors.black87,
                      ),
                    ),

                    const SizedBox(height: 40),

                    // Enter OTP Label
                    Center(
                      child: Container(
                        width: 280,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Enter OTP',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // OTP Input Boxes
                    // FIX: Use KeyboardListener to handle backspace on already-empty boxes.
                    // Previously, pressing backspace on an empty box did nothing because
                    // onChanged only fires when the value changes — it never fires on an
                    // already-empty field. Now backspace always moves focus back.
                    Center(
                      child: SizedBox(
                        width: 280,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: List.generate(6, (index) {
                            return SizedBox(
                              width: 40,
                              height: 50,
                              child: KeyboardListener(
                                focusNode: FocusNode(skipTraversal: true),
                                onKeyEvent: (event) {
                                  // FIX: Handle backspace on an already-empty box.
                                  // onChanged never fires for backspace when field is empty,
                                  // so we catch it here and move focus to previous box.
                                  if (event is KeyDownEvent &&
                                      event.logicalKey == LogicalKeyboardKey.backspace &&
                                      _otpControllers[index].text.isEmpty &&
                                      index > 0) {
                                    _focusNodes[index - 1].requestFocus();
                                  }
                                },
                                child: TextField(
                                  controller: _otpControllers[index],
                                  focusNode: _focusNodes[index],
                                  keyboardType: TextInputType.number,
                                  textAlign: TextAlign.center,
                                  maxLength: 1,
                                  autofocus: index == 0,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                  style: GoogleFonts.inter(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87,
                                  ),
                                  decoration: const InputDecoration(
                                    counterText: '',
                                    filled: true,
                                    // FIX: Replace withOpacity() (allocates a new Color object
                                    // every build call) with a pre-computed const hex value.
                                    // 0xCC = 80% opacity on white = #CCFFFFFF
                                    fillColor: Color(0xCCFFFFFF),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.all(Radius.circular(12)),
                                      borderSide: BorderSide(
                                        color: Color(0x4D000000), // black @ 30%
                                        width: 1.5,
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.all(Radius.circular(12)),
                                      borderSide: BorderSide(
                                        color: Color(0x4D000000), // black @ 30%
                                        width: 1.5,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.all(Radius.circular(12)),
                                      borderSide: BorderSide(
                                        color: Colors.black,
                                        width: 2,
                                      ),
                                    ),
                                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                                  ),
                                  onChanged: (value) {
                                    if (value.isNotEmpty && index < 5) {
                                      _focusNodes[index + 1].requestFocus();
                                    } else if (value.isEmpty && index > 0) {
                                      _focusNodes[index - 1].requestFocus();
                                    }
                                  },
                                ),
                              ),
                            );
                          }),
                        ),
                      ),
                    ),

                    const SizedBox(height: 50),

                    // Verify OTP Button — shows spinner while verifying
                    AnimatedOpacity(
                      opacity: _isOtpComplete ? 1.0 : 0.5,
                      duration: const Duration(milliseconds: 200),
                      child: GestureDetector(
                        onTap: (_isOtpComplete && !_isVerifying) ? _verifyOtp : null,
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
                          child: _isVerifying
                              ? const SizedBox(
                                  height: 24,
                                  width: 24,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : Text(
                                  'Verify OTP',
                                  style: GoogleFonts.inter(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Didn't receive OTP
                    Text(
                      "Didn't receive OTP?",
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: Colors.black87,
                      ),
                    ),

                    const SizedBox(height: 4),

                    // FIX: Resend button and timer now use ValueListenableBuilder.
                    // Previously these called setState every second (via startTimer)
                    // rebuilding the ENTIRE screen. Now only these tiny widgets rebuild.
                    ValueListenableBuilder<bool>(
                      valueListenable: _canResendNotifier,
                      builder: (context, canResend, _) {
                        return canResend
                            ? GestureDetector(
                                onTap: _resendOtp,
                                child: Text(
                                  'Resend',
                                  style: GoogleFonts.inter(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFFE60D11),
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              )
                            : Text(
                                'Resend',
                                style: GoogleFonts.inter(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey,
                                ),
                              );
                      },
                    ),

                    const SizedBox(height: 8),

                    // FIX: Timer text uses ValueListenableBuilder — zero setState calls
                    // per second on the parent widget. Only this Text rebuilds.
                    ValueListenableBuilder<bool>(
                      valueListenable: _canResendNotifier,
                      builder: (context, canResend, _) {
                        if (canResend) return const SizedBox.shrink();
                        return ValueListenableBuilder<int>(
                          valueListenable: _timerNotifier,
                          builder: (context, seconds, _) {
                            return Text(
                              'Resend available in ${seconds}s',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: Colors.black87,
                              ),
                            );
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 40),

                    // Back Button — rises above keyboard naturally
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Back',
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),
                  ],        // closes Column children
                ),          // closes Column
              ),            // closes SingleChildScrollView
            ),              // closes SafeArea
          ),                // closes Container
        );                  // closes Scaffold
      }
    }
