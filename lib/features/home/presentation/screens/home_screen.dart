import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart'; 
import 'package:emergency108_app/core/theme/app_theme.dart'; 
import 'package:stomp_dart_client/stomp.dart';
import 'package:stomp_dart_client/stomp_config.dart';
import 'package:stomp_dart_client/stomp_frame.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_pallete.dart';
import '../../../../core/config/app_config.dart';
import '../../../../features/emergency/data/emergency_repository.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../emergency/presentation/widgets/ownership_modal.dart';
import '../../../ai_doctor/presentation/screens/ai_first_aid_screen.dart';
import '../../../helping_hand/data/helping_hand_repository.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:flutter_contacts/flutter_contacts.dart';
import '../../../helping_hand/presentation/screens/helping_hand_screen.dart';
import '../../../settings/data/preferences_repository.dart';
import '../../../settings/presentation/settings_screen.dart';
import '../../../settings/presentation/about_screen.dart';
import '../../../../core/services/fcm_notification_service.dart';
import '../../../../core/services/emergency_sound_service.dart';

// New Widgets
import '../widgets/sos_activation_button.dart';
import '../widgets/emergency_countdown_view.dart';
import '../widgets/emergency_tracking_view.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _controller;
  // _holdController removed (moved to SosActivationButton)
  
  bool _isEmergencyActive = false;
  int _countdown = 0;
  // FIX: ValueNotifier for the countdown so ONLY EmergencyCountdownView
  // rebuilds every second — not the entire HomeScreen with bottom nav,
  // all tabs, SOS button, contacts, etc. Previously setState was called
  // 100 times (once per second for 100s) rebuilding the whole tree.
  final ValueNotifier<int> _countdownNotifier = ValueNotifier(0);
  Timer? _timer;
  Timer? _helpingHandTimer;
  int? _emergencyId;
  // ValueNotifier so OwnershipModal can reactively show buttons the moment
  // the real id arrives from the API, without passing the value at build time.
  final ValueNotifier<int?> _emergencyIdNotifier = ValueNotifier(null);
  String? _statusMessage;
  Map<String, dynamic>? _trackingData;
  int _currentIndex = 0;
  List<String> _emergencyContacts = [];
  bool _hasAutoCalled = false;
  bool _isDispatched = false;
  bool _isSelfEmergency = false;
  bool _isRestoringEmergency = true;
  bool _isCreatingEmergency = false;
  bool _isManualDispatching = false;
  int _helpingHandRefreshVersion = 0;
  StompClient? _trackingStompClient;
  // Location service stream — automatically cancels emergency if GPS is disabled
  StreamSubscription<ServiceStatus>? _locationServiceSubscription;
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadContacts();
    _checkProfileStatus();
    unawaited(_restoreActiveEmergencySession());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_startHelpingHandService());
    });
    _controller = AnimationController(
       vsync: this,
       duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    // Listen for GPS being turned off while user has an active emergency.
    _locationServiceSubscription = Geolocator.getServiceStatusStream().listen((status) {
      if (status == ServiceStatus.disabled && _isEmergencyActive && mounted) {
        _handleLocationServiceDisabled();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      if (_isEmergencyActive && _emergencyId != null) {
        // Re-fetch tracking to refresh stale data after coming back from background
        _fetchInitialTrackingData(_emergencyId!);
      } else if (!_isEmergencyActive && !_isRestoringEmergency) {
        // Check if an emergency was created/completed while app was in background
        unawaited(_restoreActiveEmergencySession());
      }
    }
  }

  void _checkProfileStatus() async {
    // No artificial delay needed — SharedPreferences.getInstance() is fast
    // and the dialog is only shown after prefs are read.
    final prefs = await SharedPreferences.getInstance();
    final isComplete = prefs.getBool('is_profile_complete') ?? false;

    if (!isComplete && mounted) {
      _showCompleteProfileDialog();
    }
  }

  // Stream subscription for foreground notifications
  StreamSubscription? _fcmSubscription;

  Future<void> _startHelpingHandService() async {
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString('user_role');
    
    // Initialize FCM for all users to get foreground alerts
    final fcmService = FCMNotificationService();
    final fcmToken = await fcmService.initialize().timeout(
      const Duration(seconds: 6),
      onTimeout: () {
        debugPrint('⚠️ FCM init timed out, continuing startup without token');
        return null;
      },
    );
    fcmService.setupForegroundHandler();

    // Register FCM token with backend so server can push notifications to this device
    if (fcmToken != null) {
      try {
        final authRepo = ref.read(authRepositoryProvider);
        await authRepo.registerFcmToken(fcmToken);
        debugPrint('✅ FCM token registered with backend');
      } catch (e) {
        debugPrint('⚠️ Failed to register FCM token: $e');
      }
    }
    
    // Listen for foreground alerts
    _fcmSubscription = fcmService.onForegroundMessage.listen((message) {
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(
               content: Text(message.notification?.body ?? '🚨 Emergency Alert!'),
               backgroundColor: Colors.redAccent, // Red for visibility
               duration: const Duration(seconds: 10), // Longer duration
               action: SnackBarAction(
                 label: 'VIEW', 
                 textColor: Colors.white,
                 onPressed: () {
                    // Navigate based on data, e.g. helping hand tab
                    if (message.data['type'] == 'helping_hand') {
                        setState(() {
                          _currentIndex = 2;
                          _helpingHandRefreshVersion++;
                        });
                    }
                 },
               ),
             ),
           );
        }
    });

    // Handle notification tap from background/terminated state for public users.
    fcmService.setupNotificationTapHandler((data) {
      if (!mounted) return;
      if (data['type'] == 'helping_hand') {
        setState(() {
          _currentIndex = 2;
          _helpingHandRefreshVersion++;
        });
      }
    });
    
    // Only PUBLIC users participate as helpers - Push Notification Only
    if (role == 'PUBLIC') {
        _updateLocationOnly();
    }
  }

  Future<void> _updateLocationOnly() async {
    final prefsRepo = ref.read(preferencesRepositoryProvider);
    if (!await prefsRepo.isHelpingHandEnabled()) return;

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

      final position = await Geolocator.getCurrentPosition();

      final helpingHandRepo = ref.read(helpingHandRepositoryProvider);
      await helpingHandRepo.updateLocation(position.latitude, position.longitude);
      debugPrint("📍 Location updated for Push Notifications");

    } catch (e) {
      debugPrint("❌ Error updating location: $e");
    }
  }

  void _showCompleteProfileDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Complete Your Profile'),
        content: const Text('To ensure better safety, please complete your profile with your name and address.'),
        actions: [
          ElevatedButton(
            onPressed: () {
              context.pop();
              context.push('/profile');
            },
            child: const Text('Setup Now'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    _timer?.cancel();
    _helpingHandTimer?.cancel();
    _fcmSubscription?.cancel();
    _locationServiceSubscription?.cancel();
    _emergencyIdNotifier.dispose();
    _countdownNotifier.dispose();
    _trackingStompClient?.deactivate();
    unawaited(EmergencySoundService().stop());
    super.dispose();
  }

  Future<void> _loadContacts() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _emergencyContacts = prefs.getStringList('emergency_contacts') ?? [];
    });
  }

  Future<void> _saveContacts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('emergency_contacts', _emergencyContacts);
  }

  Future<void> _persistActiveEmergencyId(int emergencyId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('active_emergency_id', emergencyId);
  }

  Future<void> _clearPersistedActiveEmergencyId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('active_emergency_id');
  }

  Future<void> _restoreActiveEmergencySession() async {
    try {
      final emergencyRepo = ref.read(emergencyRepositoryProvider);
      final active = await emergencyRepo.getMyActiveEmergency();

      if (active == null) {
        await _clearPersistedActiveEmergencyId();
        return;
      }

      final rawId = active['id'];
      final emergencyId = rawId is int ? rawId : int.tryParse(rawId.toString());
      if (emergencyId == null) {
        await _clearPersistedActiveEmergencyId();
        return;
      }

      _isSelfEmergency = (active['emergencyFor']?.toString() ?? 'UNKNOWN') == 'SELF';
      _emergencyIdNotifier.value = emergencyId;
      await _persistActiveEmergencyId(emergencyId);

      if (!mounted) return;
      final status = active['status']?.toString() ?? '';
      final isAlreadyDispatched = const {'DISPATCHED', 'IN_PROGRESS', 'AT_PATIENT', 'TO_HOSPITAL'}.contains(status);
      setState(() {
        _isEmergencyActive = true;
        _emergencyId = emergencyId;
        _isDispatched = isAlreadyDispatched;
        _statusMessage = 'Restoring your active emergency...';
        _countdown = 0;
      });
      _countdownNotifier.value = 0;

      // Pull latest tracking immediately, then keep listening on STOMP.
      await _fetchInitialTrackingData(emergencyId);
      _pollStatus();

      // Schedule auto-call if this is a SELF emergency that was already dispatched
      if (_isSelfEmergency && isAlreadyDispatched && !_hasAutoCalled) {
        _hasAutoCalled = true;
        _scheduleAutoCall();
      }
    } catch (e) {
      debugPrint('⚠️ Could not restore active emergency session: $e');
    } finally {
      if (mounted) {
        setState(() => _isRestoringEmergency = false);
      }
    }
  }

  void _showEmergencyContactsDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setStateDialog) {
            Future<void> addFromContacts() async {
              // Close the dialog first so the contact picker is on top
              Navigator.of(dialogContext).pop();
              try {
                await FlutterContacts.requestPermission();
                final picked = await FlutterContacts.openExternalPick();
                if (picked != null) {
                  final full = await FlutterContacts.getContact(picked.id, withProperties: true);
                  final name = full?.displayName ?? 'Contact';
                  final number = full?.phones.firstOrNull?.number ?? '';
                  if (number.isNotEmpty) {
                    setState(() {
                      _emergencyContacts.add('$name|$number');
                    });
                    await _saveContacts();
                    // Re-open dialog to show the newly added contact
                    if (mounted) _showEmergencyContactsDialog();
                  } else {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Selected contact has no phone number.')),
                      );
                      _showEmergencyContactsDialog();
                    }
                  }
                } else {
                  // User cancelled picker — reopen dialog
                  if (mounted) _showEmergencyContactsDialog();
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Could not access contacts. Please grant permission.')),
                  );
                  _showEmergencyContactsDialog();
                }
              }
            }

            void addManually() {
              final nameCtrl = TextEditingController();
              final phoneCtrl = TextEditingController();
              showDialog(
                context: dialogContext,
                builder: (ctx) => AlertDialog(
                  backgroundColor: Colors.white,
                  title: const Text('Add Contact Manually'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameCtrl,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Name',
                          prefixIcon: Icon(Icons.person_outline),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: phoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Phone Number',
                          prefixIcon: Icon(Icons.phone_outlined),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppPallete.primary,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () {
                        final name = nameCtrl.text.trim();
                        final phone = phoneCtrl.text.trim();
                        if (name.isEmpty || phone.isEmpty) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(content: Text('Please enter both name and phone number.')),
                          );
                          return;
                        }
                        setStateDialog(() {
                          _emergencyContacts.add('$name|$phone');
                        });
                        _saveContacts();
                        Navigator.pop(ctx); // close manual entry dialog
                      },
                      child: const Text('Add'),
                    ),
                  ],
                ),
              );
            }

            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: const [
                  Icon(Icons.contacts, color: Color(0xFFE60D11)),
                  SizedBox(width: 8),
                  Text('Emergency Contacts', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.amber.shade200),
                      ),
                      child: Row(
                        children: const [
                          Icon(Icons.info_outline, size: 16, color: Colors.amber),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'These contacts are auto-dialled 1 min after an emergency is dispatched.',
                              style: TextStyle(fontSize: 12, color: Colors.black87),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Contact list
                    if (_emergencyContacts.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text('No contacts added yet.',
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                      ),
                    ..._emergencyContacts.map((c) {
                      final parts = c.split('|');
                      final name = parts.isNotEmpty ? parts[0] : 'Unknown';
                      final number = parts.length > 1 ? parts[1] : '';
                      return Card(
                        elevation: 0,
                        color: Colors.grey.shade50,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(color: Colors.grey.shade200),
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFFFFEEEE),
                            child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                              style: const TextStyle(color: Color(0xFFE60D11), fontWeight: FontWeight.bold)),
                          ),
                          title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(number, style: const TextStyle(fontFamily: 'monospace')),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            onPressed: () {
                              setStateDialog(() => _emergencyContacts.remove(c));
                              _saveContacts();
                            },
                          ),
                        ),
                      );
                    }).toList(),

                    // Add buttons — only if < 2 contacts
                    if (_emergencyContacts.length < 2) ...[
                      const SizedBox(height: 16),
                      const Text('Add a contact:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              label: const Text('Manually', style: TextStyle(fontSize: 13)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.black87,
                                side: const BorderSide(color: Colors.black26),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              onPressed: addManually,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.contacts_outlined, size: 18),
                              label: const Text('From Contacts', style: TextStyle(fontSize: 13)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppPallete.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              onPressed: addFromContacts,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Done', style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w600)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _normalizePhoneNumber(String input) {
    final trimmed = input.trim();
    final hasPlusPrefix = trimmed.startsWith('+');
    final digitsOnly = trimmed.replaceAll(RegExp(r'\D'), '');
    if (digitsOnly.isEmpty) return '';
    return hasPlusPrefix ? '+$digitsOnly' : digitsOnly;
  }

  List<String> _extractEmergencyContactNumbers() {
    final numbers = <String>[];
    for (final contact in _emergencyContacts) {
      final parts = contact.split('|');
      if (parts.length < 2) continue;
      final normalized = _normalizePhoneNumber(parts[1]);
      if (normalized.isNotEmpty) {
        numbers.add(normalized);
      }
    }
    return numbers;
  }

  Future<bool> _callContactWithFallback(String phoneNumber) async {
    // Try direct call first when CALL_PHONE is granted.
    final phonePermission = await ph.Permission.phone.request();
    if (phonePermission.isGranted) {
      try {
        final directCallSuccess = await FlutterPhoneDirectCaller.callNumber(phoneNumber);
        if (directCallSuccess == true) {
          return true;
        }
        debugPrint('⚠️ Direct call returned false for $phoneNumber. Falling back to dialer.');
      } catch (error) {
        debugPrint('⚠️ Direct call failed for $phoneNumber: $error');
      }
    } else {
      debugPrint('⚠️ CALL_PHONE permission not granted. Falling back to dialer for $phoneNumber.');
    }

    // Fallback: open the phone dialer with number prefilled.
    final uri = Uri(scheme: 'tel', path: phoneNumber);
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _ensureAutoCallPermissionReady() async {
    final currentStatus = await ph.Permission.phone.status;
    if (currentStatus.isGranted) return;

    final requested = await ph.Permission.phone.request();
    if (requested.isGranted) return;

    if (!mounted) return;

    if (requested.isPermanentlyDenied) {
      await showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Phone Permission Required'),
          content: const Text(
            'Automatic emergency contact calling needs phone permission. '
            'Please enable it from app settings.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Not Now'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                await ph.openAppSettings();
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppPallete.error),
              child: const Text('Open Settings'),
            ),
          ],
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Phone permission is needed for automatic emergency calling.'),
        backgroundColor: AppPallete.error,
      ),
    );
  }

  void _scheduleAutoCall() {
    if (_emergencyContacts.isEmpty || !_isSelfEmergency) {
      return;
    }

    // Ask permission ahead of the 60s timer so auto-calling is not blocked later.
    unawaited(_ensureAutoCallPermissionReady());

    Timer(const Duration(seconds: 60), () async {
      if (!_isEmergencyActive || _trackingData?['status'] == 'COMPLETED') return; // Cancel if resolved

      final numbers = _extractEmergencyContactNumbers();
      if (numbers.isEmpty) {
        debugPrint('⚠️ No valid emergency contact numbers available for auto-call.');
        return;
      }

      bool callPlaced = false;
      for (final number in numbers) {
        callPlaced = await _callContactWithFallback(number);
        if (callPlaced) break;
      }

      if (!callPlaced && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to initiate emergency contact call. Please call manually.'),
            backgroundColor: AppPallete.error,
          ),
        );
      }
    });
  }

  void _createEmergency() async {
    if (_isEmergencyActive || _isCreatingEmergency || _isRestoringEmergency) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('An emergency is already active. Please complete or cancel it first.'),
          backgroundColor: AppPallete.error,
        ),
      );
      return;
    }
    _isCreatingEmergency = true;

    // GUARD: Location must be available before creating an emergency.
    // Dispatching with hardcoded coordinates would send the ambulance to the
    // wrong city — block and show a clear actionable dialog instead.
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return;
      _showLocationRequiredDialog(openSettings: false);
      _isCreatingEmergency = false;
      return;
    }
    LocationPermission locPermission = await Geolocator.checkPermission();
    if (locPermission == LocationPermission.denied) {
      locPermission = await Geolocator.requestPermission();
    }
    if (locPermission == LocationPermission.denied ||
        locPermission == LocationPermission.deniedForever) {
      if (!mounted) return;
      _showLocationRequiredDialog(
          openSettings: locPermission == LocationPermission.deniedForever);
      _isCreatingEmergency = false;
      return;
    }

    setState(() {
      _hasAutoCalled = false;
      _isDispatched = false;
      _isSelfEmergency = false;
    });

    // FIX: Show the ownership modal IMMEDIATELY on button tap — do not wait
    // for GPS or the network API call. Previously the sequence was:
    //   await GPS (3–15 sec with HIGH accuracy)  →  await API call  →  show modal
    // That's why "Who needs help?" appeared so late.
    //
    // New approach:
    //   1. Show the modal right away (instant feedback to the user)
    //   2. Get GPS using MEDIUM accuracy (network-based, < 1 sec) with a short
    //      timeout, falling back to the default coords if it takes too long.
    //   3. Fire the API call in the background while the user is choosing.
    //   4. If the API call fails, dismiss the modal and show an error.

    // Step 1 — Show the ownership modal immediately so the user isn't staring
    // at a frozen screen waiting for GPS + network.
    _emergencyIdNotifier.value = null; // reset
    setState(() {
      _isEmergencyActive = true;
      _countdown = 100;
      _statusMessage = "Emergency Created!";
    });
    _countdownNotifier.value = 100; // sync notifier for ValueListenableBuilder in EmergencyCountdownView

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => OwnershipModal(
        emergencyIdNotifier: _emergencyIdNotifier,
        onDecisionMade: (ownership) {
          _isSelfEmergency = ownership == 'SELF';
          // If dispatch already happened before user chose ownership,
          // trigger the auto-call now that we know it's SELF.
          if (_isSelfEmergency && _isDispatched && !_hasAutoCalled) {
            _hasAutoCalled = true;
            _scheduleAutoCall();
          }
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Preference Saved', style: TextStyle(color: Colors.white)),
              backgroundColor: AppPallete.success,
            ),
          );
        },
        onCancel: () {
          _cancelEmergency();
        },
      ),
    );

    // Step 2 — Get GPS with MEDIUM accuracy (network-based, near-instant).
    // HIGH accuracy uses the satellite chip and takes 3–15 sec indoors.
    double lat = 28.6139; // fallback: New Delhi
    double lng = 77.2090;
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission != LocationPermission.deniedForever &&
          await Geolocator.isLocationServiceEnabled()) {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            // FIX: Use medium accuracy (cell/WiFi triangulation) — available in
            // < 1 second. We already showed the modal so the user is busy
            // choosing; they won't notice this is happening in the background.
            accuracy: LocationAccuracy.medium,
          ),
        ).timeout(
          const Duration(seconds: 5),
          onTimeout: () => Geolocator.getLastKnownPosition().then(
            (p) => p ?? Position(
              latitude: lat, longitude: lng,
              timestamp: DateTime.now(), accuracy: 0,
              altitude: 0, altitudeAccuracy: 0,
              heading: 0, headingAccuracy: 0, speed: 0, speedAccuracy: 0,
            ),
          ),
        );
        lat = position.latitude;
        lng = position.longitude;
      }
    } catch (locErr) {
      debugPrint('⚠️ Could not get GPS location, using fallback: $locErr');
    }

    // Step 3 — Create emergency on backend with the coordinates we have.
    try {
      final result = await ref.read(emergencyRepositoryProvider).createEmergency(
        lat: lat,
        lng: lng,
      );
      final createdEmergencyId = result['id'] is int
          ? result['id'] as int
          : int.tryParse(result['id'].toString());
      if (createdEmergencyId == null) {
        throw Exception('Invalid emergency id from server');
      }

      if (!mounted) return;

      setState(() {
        _emergencyId = createdEmergencyId;
      });
      await _persistActiveEmergencyId(createdEmergencyId);
      // Notify the already-open OwnershipModal so buttons become tappable.
      _emergencyIdNotifier.value = createdEmergencyId;

      _startCountdown();
      _isCreatingEmergency = false;
    } catch (e) {
      // Step 4 — API failed: undo the optimistic UI and close the modal.
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
      _emergencyIdNotifier.value = null;
      setState(() {
        _isEmergencyActive = false;
        _emergencyId = null;
        _statusMessage = null;
        _countdown = 0;
      });
      _countdownNotifier.value = 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: AppPallete.error),
      );
      _isCreatingEmergency = false;
    }
  }

  void _startCountdown() {
    unawaited(EmergencySoundService().playDispatchTone());

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown > 0) {
        // FIX: Update ONLY the notifier — no setState — so only the
        // EmergencyCountdownView widget rebuilds each second instead of
        // the entire HomeScreen tree (100 full rebuilds avoided).
        _countdownNotifier.value = --_countdown;
      } else {
        _timer?.cancel();
        _isDispatched = true;
        unawaited(EmergencySoundService().stop());
        
        // Auto-Dispatcher triggered: Close "Who needs help?" modal if open
        if (_isEmergencyActive && _statusMessage == "Emergency Created!" && mounted) {
           Navigator.of(context).popUntil((route) => route.isFirst); // Clear modals
        }

        setState(() => _statusMessage = "Dispatching...");
        _pollStatus();
      }
    });
  }
  
  void _manualDispatch() async {
    if (_emergencyId == null || _isManualDispatching) return;
    _isManualDispatching = true;
    try {
       _isDispatched = true;
       await EmergencySoundService().stop();
       await ref.read(emergencyRepositoryProvider).dispatchEmergency(_emergencyId!);
       _timer?.cancel();
       
       // Close modal if open (Manual dispatch overrides safety net wait)
       // Navigator.of(context).popUntil((route) => route.isFirst); 

       setState(() {
         _countdown = 0;
         _statusMessage = "Dispatched! Finding Driver...";
       });
       _countdownNotifier.value = 0;
       _pollStatus();
    } catch (e) {
       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
     } finally {
       _isManualDispatching = false;
    }
  }

  void _showLocationRequiredDialog({required bool openSettings}) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Location Required'),
        content: const Text(
          'Emergency dispatch requires your location to send the nearest '
          'ambulance. Please enable location services and try again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppPallete.error),
            onPressed: () async {
              Navigator.pop(context);
              if (openSettings) {
                await Geolocator.openAppSettings();
              } else {
                await Geolocator.openLocationSettings();
              }
            },
            child: Text(
              openSettings ? 'Open App Settings' : 'Enable Location',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  /// Called when GPS is turned off while an emergency is active.
  /// Warns the user and gives them the option to re-enable GPS or cancel.
  void _handleLocationServiceDisabled() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        icon: const Icon(Icons.location_off_rounded, color: Colors.red, size: 50),
        title: const Text('Location Disabled'),
        content: const Text(
          'You turned off GPS while an emergency was active. '
          'The ambulance cannot navigate to you without your location. '
          'Please re-enable GPS immediately.',
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await Geolocator.openLocationSettings();
            },
            child: const Text('Enable GPS'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(context);
              _cancelEmergency();
            },
            child: const Text('Cancel Emergency'),
          ),
        ],
      ),
    );
  }

  void _cancelEmergency() async {
    if (_emergencyId == null) return;
    
    // Check if it's a late cancellation (Driver Assigned/Accepted, etc.)
    final status = _trackingData?['status'];
    bool isLateCancellation = status == 'DISPATCHED' || status == 'IN_PROGRESS' || status == 'AT_PATIENT' || status == 'TO_HOSPITAL';

    String? cancellationReason;

    if (isLateCancellation) {
      cancellationReason = await _showCancellationReasonDialog();
      if (cancellationReason == null) return; // User dismissed dialog without selecting
    }

    try {
      await EmergencySoundService().stop();
      await ref.read(emergencyRepositoryProvider).cancelEmergency(_emergencyId!, reason: cancellationReason);
      _timer?.cancel();
      _trackingStompClient?.deactivate();
      _emergencyIdNotifier.value = null;
      setState(() {
        _isEmergencyActive = false;
        _emergencyId = null;
        _trackingData = null;
        _statusMessage = null;
        _hasAutoCalled = false;
        _countdown = 0;
      });
      
      // Navigate to Home Tab (reset state)
      setState(() => _currentIndex = 0); 
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Emergency Cancelled'), backgroundColor: AppPallete.grey),
      );
      await _clearPersistedActiveEmergencyId();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<String?> _showCancellationReasonDialog() async {
    String? selectedReason;
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Cancel Emergency?'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   const Text('The driver has already been assigned. Please tell us why you are cancelling:'),
                   const SizedBox(height: 20),
                   _buildRadioOption("Mistakenly created", selectedReason, (val) => setDialogState(() => selectedReason = val)),
                   _buildRadioOption("Driver is too far", selectedReason, (val) => setDialogState(() => selectedReason = val)),
                   _buildRadioOption("Found alternative transport", selectedReason, (val) => setDialogState(() => selectedReason = val)),
                   _buildRadioOption("Emergency resolved", selectedReason, (val) => setDialogState(() => selectedReason = val)),
                   _buildRadioOption("Other", selectedReason, (val) => setDialogState(() => selectedReason = val)),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context), 
                  child: const Text('Don\'t Cancel'),
                ),
                ElevatedButton(
                  onPressed: selectedReason != null 
                    ? () => Navigator.pop(context, selectedReason) 
                    : null,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                  child: const Text('Confirm Cancellation'),
                ),
              ],
            );
          }
        );
      },
    );
  }

  Widget _buildRadioOption(String value, String? groupValue, ValueChanged<String?> onChanged) {
    return RadioListTile<String>(
      title: Text(value, style: GoogleFonts.inter(fontSize: 14)),
      value: value,
      groupValue: groupValue,
      onChanged: onChanged,
      contentPadding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      activeColor: AppPallete.primary,
    );
  }

  /// Replaces the old HTTP-polling timer with a persistent STOMP subscription.
  /// The Flutter patient app subscribes to /topic/emergency/{id}/tracking
  /// which the backend broadcasts on every driver GPS tick and every status
  /// transition — giving sub-second updates with zero polling overhead.
  void _pollStatus() {
    if (_emergencyId == null) return;
    final emergencyId = _emergencyId!;

    // Clean up any leftover client from a previous emergency
    _trackingStompClient?.deactivate();

    // Immediately fetch current tracking state via REST so the tracking view
    // shows right away without having to wait for the first STOMP heartbeat.
    _fetchInitialTrackingData(emergencyId);

    SharedPreferences.getInstance().then((prefs) {
      final token = prefs.getString('auth_token');
      if (token == null || !mounted) return;

      _trackingStompClient = StompClient(
        config: StompConfig.sockJS(
          url: '${AppConfig.wsBaseUrl}/ws',
          stompConnectHeaders: {'Authorization': 'Bearer $token'},
          reconnectDelay: const Duration(seconds: 5),
          onConnect: (StompFrame frame) {
            debugPrint('🟢 [Tracking] STOMP connected for emergency $emergencyId');
            _trackingStompClient?.subscribe(
              destination: '/topic/emergency/$emergencyId/tracking',
              callback: (StompFrame msg) {
                if (msg.body == null || !mounted) return;
                try {
                  final data = Map<String, dynamic>.from(
                      json.decode(msg.body!) as Map);
                  setState(() {
                    _trackingData = data;
                    _statusMessage = data['message'] as String?;
                  });

                  final status = data['status'] as String?;

                  // Mark dispatched and trigger auto-call if SELF ownership
                  // was already decided. If ownership decision comes later,
                  // the onDecisionMade callback will trigger it instead.
                  if (status == 'DISPATCHED' || status == 'IN_PROGRESS') {
                    _isDispatched = true;
                    if (_isSelfEmergency && !_hasAutoCalled) {
                      _hasAutoCalled = true;
                      _scheduleAutoCall();
                    }
                  }

                  if (status == 'COMPLETED') {
                    _trackingStompClient?.deactivate();
                    unawaited(_clearPersistedActiveEmergencyId());
                    // Let the tracking view render the COMPLETED timeline step
                    // fully before the dialog blocks the screen.
                    Future.delayed(const Duration(seconds: 3), () {
                      if (mounted) _showCompletionDialog();
                    });
                  } else if (status == 'CANCELLED') {
                    // Admin cancelled the emergency
                    _trackingStompClient?.deactivate();
                    unawaited(_clearPersistedActiveEmergencyId());
                    final cancelledBy = (data['cancelledBy'] as String?)
                        ?.isNotEmpty == true
                        ? data['cancelledBy'] as String
                        : 'Admin';
                    if (mounted) _showAdminCancelledDialog(cancelledBy);
                  }
                } catch (e) {
                  debugPrint('🔴 [Tracking] Bad payload: $e');
                }
              },
            );
          },
          onWebSocketError: (dynamic e) =>
              debugPrint('🔴 [Tracking] WS error: $e'),
          onStompError: (StompFrame f) =>
              debugPrint('🔴 [Tracking] STOMP error: ${f.headers}'),
          onDisconnect: (StompFrame _) =>
              debugPrint('🟡 [Tracking] STOMP disconnected'),
        ),
      );
      _trackingStompClient!.activate();
    });
  }

  /// Performs a one-off REST fetch to get the latest tracking snapshot
  /// immediately when tracking starts — avoids blank screen while waiting
  /// for the first STOMP broadcast (which only arrives on next GPS heartbeat).
  Future<void> _fetchInitialTrackingData(int emergencyId) async {
    try {
      final data = await ref.read(emergencyRepositoryProvider).trackEmergency(emergencyId);
      if (mounted && _emergencyId == emergencyId) {
        setState(() {
          _trackingData = data;
          _statusMessage = data['message'] as String?;
        });
      }
    } catch (e) {
      // Non-fatal — STOMP will provide the first update shortly
      debugPrint('⚠️ Initial tracking fetch failed: $e');
    }
  }

  /// Called when admin cancels the emergency via the admin panel.
  /// Resets all state, closes any open dialogs, and shows a clear dialog.
  void _showAdminCancelledDialog(String cancelledBy) {
    // Reset all emergency state first
    _timer?.cancel();
    _trackingStompClient?.deactivate();
    unawaited(EmergencySoundService().stop());
    _emergencyIdNotifier.value = null;
    Navigator.of(context).popUntil((route) => route.isFirst);
    setState(() {
      _isEmergencyActive = false;
      _emergencyId = null;
      _trackingData = null;
      _statusMessage = null;
      _hasAutoCalled = false;
      _countdown = 0;
      _currentIndex = 0;
    });
    _countdownNotifier.value = 0;
    unawaited(_clearPersistedActiveEmergencyId());

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.cancel_outlined, color: Colors.red, size: 56),
        title: const Text('Emergency Cancelled'),
        content: Text(
          'Your emergency was cancelled by $cancelledBy. '
          'If you still need help, please create a new emergency.',
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showCompletionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Emergency Resolved'),
        content: const Text('The emergency has been marked as completed. We hope you are safe.'),
        actions: [
          ElevatedButton(
            onPressed: () {
               unawaited(EmergencySoundService().stop());
               context.pop();
               setState(() {
                 _isEmergencyActive = false;
                 _emergencyId = null;
                 _hasAutoCalled = false;
                 _trackingData = null;
                 _statusMessage = null;
                 _countdown = 0;
               });
               unawaited(_clearPersistedActiveEmergencyId());
            },
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true, // Allow gradient to show through
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppTheme.backgroundGradient,
        ),
        child: SafeArea( // Ensure content is safe
          child: Column(
            children: [
               _buildCustomAppBar(),
              Expanded(
                child: IndexedStack(
                  index: _currentIndex,
                  children: [
                    // TAB 0: Home (SOS)
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      child: _isEmergencyActive
                        ? _buildActiveState()
                        : _isRestoringEmergency
                            ? const Center(
                                child: CircularProgressIndicator(color: AppPallete.primary),
                              )
                        : SosActivationButton(
                            key: const ValueKey('sos_btn'),
                            onEmergencyTriggered: _createEmergency,
                          ),
                    ),
                    
                    // TAB 1: AI Assistant
                    AiFirstAidScreen(emergencyId: _emergencyId), 
                    
                    // TAB 2: Helping Hand
                    HelpingHandScreen(key: ValueKey('helping_hand_$_helpingHandRefreshVersion')),
                  ],
                ),
              ),
              _buildCustomBottomNav(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCustomAppBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Profile Icon (Top Left)
          GestureDetector(
            onTap: () => context.push('/profile'),
            child: CircleAvatar(
              radius: 24,
              backgroundColor: AppPallete.primary.withOpacity(0.1),
              // TODO: Fetch image from user preferences if available
              child: const Icon(Icons.person, color: AppPallete.primary, size: 28),
            ),
          ),
          
          // App Title (Top Center)
          Text(
            'emergency108',
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: AppPallete.primary, // Red text for light theme
            ),
          ),
          
          // Custom Menu Icon (Top Right)
          PopupMenuButton<String>(
            color: Colors.white,
            offset: const Offset(0, 50),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            child: Container(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                   _buildHollowDot(),
                   const SizedBox(height: 3),
                   _buildHollowDot(),
                   const SizedBox(height: 3),
                   _buildHollowDot(),
                ],
              ),
            ),
            itemBuilder: (context) => [
               const PopupMenuItem(value: 'contacts', child: Text('Emergency Contacts')),
               const PopupMenuItem(value: 'settings', child: Text('Settings')),
               const PopupMenuItem(value: 'about', child: Text('About')),
               const PopupMenuItem(value: 'logout', child: Text('Logout')),
            ],
            onSelected: (value) async {
               if (value == 'contacts') {
                 _showEmergencyContactsDialog();
               } else if (value == 'settings') {
                 Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
                       } else if (value == 'about') {
                         Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AboutScreen()));
               } else if (value == 'logout') {
                 final prefs = await SharedPreferences.getInstance();
                 await prefs.clear(); // Clear all data (token, profile, role)
                 if (context.mounted) context.go('/login');
               }
            },
          ),
        ],
      ),
    );
  }
  
  Widget _buildHollowDot() {
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppPallete.primary, width: 1.5), // Red dots
        color: Colors.transparent,
      ),
    );
  }

  Widget _buildCustomBottomNav() {
    return Container(
      height: 80,
      padding: const EdgeInsets.only(bottom: 20, left: 20, right: 20),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white, // Solid white bottom nav instead of glassy
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
             BoxShadow(
               color: Colors.black.withValues(alpha: 0.1),
               blurRadius: 10,
               offset: const Offset(0, 5),
             ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildNavItem(0, Icons.home_rounded, 'Home'),
            _buildNavItem(1, Icons.medical_services_rounded, 'AI Doctor'),
            _buildNavItem(2, Icons.favorite_rounded, 'Helping Hand'),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    bool isSelected = _currentIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Red Glossy Gradient Icon
          ShaderMask(
            shaderCallback: (Rect bounds) {
              return const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFFFF5F6D), // Glossy Top
                  Color(0xFFC70039), // Glossy Bottom
                ],
              ).createShader(bounds);
            },
            child: Icon(
              icon,
              size: isSelected ? 32 : 28,
              color: Colors.white, // Color is ignored by ShaderMask but required
            ),
          ),
          if (isSelected)
            Container(
              margin: const EdgeInsets.only(top: 4),
              width: 4,
              height: 4,
              decoration: const BoxDecoration(
                color: Color(0xFFC70039),
                shape: BoxShape.circle,
              ),
            )
        ],
      ),
    );
  }

  Widget _buildActiveState() {
    if (_trackingData != null) {
      final status = _trackingData!['status'] as String?;
      // Show the tracking map view as soon as the emergency has an assigned driver
      // or any active status — don't wait for 'ambulanceAssigned' flag which may
      // arrive late depending on backend broadcast timing.
      final bool showTrackingView =
          _trackingData!['ambulanceAssigned'] == true ||
          (status != null &&
              const {'DISPATCHED', 'IN_PROGRESS', 'AT_PATIENT', 'TO_HOSPITAL', 'COMPLETED'}
                  .contains(status));

      if (showTrackingView) {
        return EmergencyTrackingView(
          trackingData: _trackingData!,
          onCancel: _cancelEmergency,
        );
      }
    }
  
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.emergency_share, size: 80, color: AppPallete.primary),
        const SizedBox(height: 30),
        
        const SizedBox(height: 30),
        
        Text(
          _statusMessage ?? "Connecting...",
          style: GoogleFonts.poppins(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Colors.black87, // Dark text on light BG
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
         Text(
          "Auto dispatch will be done after",
          style: GoogleFonts.inter(color: Colors.black54, fontSize: 16),
        ),
        
        const SizedBox(height: 20),
        
        if (_countdown > 0)
          EmergencyCountdownView(
            countdownNotifier: _countdownNotifier,
            onManualDispatch: _manualDispatch,
          )
        else
           const Padding(
             padding: EdgeInsets.symmetric(horizontal: 40),
             child: LinearProgressIndicator(color: AppPallete.primary, backgroundColor: Colors.black12),
           ),

        const SizedBox(height: 50),
        _buildCancelButton(),
      ],
    );
  }
  
  Widget _buildCancelButton() {
    return ElevatedButton.icon(
      onPressed: _cancelEmergency,
      style: ElevatedButton.styleFrom(
        foregroundColor: Colors.white, backgroundColor: Colors.red, // Prominent red button
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      ),
      icon: const Icon(Icons.close),
      label: const Text('CANCEL EMERGENCY', style: TextStyle(fontWeight: FontWeight.bold)),
    );
  }
}
