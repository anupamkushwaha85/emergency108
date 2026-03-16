import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:emergency108_app/core/theme/app_theme.dart';
import '../../../../core/theme/app_pallete.dart';
import '../../data/driver_repository.dart';
import '../../../location/data/ws_location_service.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/services/fcm_notification_service.dart';
import '../../../../features/auth/data/auth_repository.dart';
import '../../../../core/config/app_config.dart';

// Widgets
import '../widgets/driver_app_bar.dart';
import '../widgets/driver_bottom_nav.dart';
import '../widgets/driver_dashboard_view.dart';
import '../widgets/active_mission_view.dart';
import '../widgets/verification_pending_view.dart';

class DriverHomeScreen extends ConsumerStatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  ConsumerState<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends ConsumerState<DriverHomeScreen> with WidgetsBindingObserver {
  bool _isOnline = false;
  String? _verificationStatus; 
  bool _hasUploadedVerificationDocument = false;
  bool _isLoadingInitial = true;
  // WebSocket service replaces the old _locationHeartbeatTimer
  WsLocationService? _wsLocationService;
  bool _isLoading = false;
  StreamSubscription? _fcmForegroundSubscription;
  
  // Live driver position — updated by the GPS stream via WsLocationService
  // Passed down to ActiveMissionView so the driver marker is always accurate
  Position? _currentPosition;

  // Mission State
  Map<String, dynamic>? _activeAssignment;
  String _missionStatus = 'IDLE'; 
  int? _pendingAssignmentEmergencyId;
  bool _isAssignmentDecisionInProgress = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchInitialStatus();
    _setupFCMHandlers();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      if (_isOnline && _activeAssignment != null) {
        // Re-fetch assignment to sync mission status after coming back from background
        _checkMissedAssignments();
      } else if (_isOnline && _activeAssignment == null) {
        // Check if a new assignment arrived while app was in background
        _checkMissedAssignments();
      }
    }
  }

  void _setupFCMHandlers() {
    // When a notification is tapped from background/terminated State
    FCMNotificationService().setupNotificationTapHandler((data) async {
       if (data['action'] == 'NEW_EMERGENCY' && mounted) {
          // One-time fetch to get full assignment details
          final assignment = await ref.read(driverRepositoryProvider).getAssignedEmergency();
          if (assignment != null && mounted) {
             _handleAssignmentData(assignment);
          }
       }
    });
  }

  Future<void> _fetchInitialStatus() async {
    setState(() => _isLoadingInitial = true);
    try {
      // Register FCM token with backend so driver receives push notifications
      final fcmService = FCMNotificationService();
      final fcmToken = await fcmService.initialize();
      fcmService.setupForegroundHandler();
      if (fcmToken != null) {
        try {
          await ref.read(authRepositoryProvider).registerFcmToken(fcmToken);
          debugPrint('✅ Driver FCM token registered');
        } catch (e) {
          debugPrint('⚠️ Failed to register driver FCM token: $e');
        }
      }

      // Listen for foreground FCM (assignment notifications when app is open)
      _fcmForegroundSubscription?.cancel();
      _fcmForegroundSubscription = fcmService.onForegroundMessage.listen((message) async {
        if (!mounted) return;
        final action = message.data['action'];
        if (action == 'NEW_EMERGENCY') {
          if (_activeAssignment != null) return;
          final assignment = await ref.read(driverRepositoryProvider).getAssignedEmergency();
          if (assignment != null && mounted) {
            _handleAssignmentData(assignment);
          }
        }
      });

      final verificationInfo = await ref.read(driverRepositoryProvider).getVerificationInfo();
      final verifyStatus = verificationInfo['verificationStatus']?.toString() ?? 'PENDING';
      final hasDocument = verificationInfo['hasDocument'] == true;

      // Only call getSessionState if VERIFIED — endpoint rejects unverified drivers
      bool onlineStatus = false;
      bool hasOngoingMission = false;
      if (verifyStatus == 'VERIFIED') {
        final sessionState = await ref.read(driverRepositoryProvider).getSessionState();
        onlineStatus = sessionState['isOnline'] as bool;
        hasOngoingMission = sessionState['hasOngoingMission'] as bool;
      }

      if (mounted) {
        setState(() {
          _verificationStatus = verifyStatus;
          _hasUploadedVerificationDocument = hasDocument;
          // ON_TRIP drivers are "online" — they have an active mission even if the
          // getDriverStatus isOnline was previously returning false before our fix.
          _isOnline = onlineStatus || hasOngoingMission;
          _isLoadingInitial = false;
        });

        if (_isOnline) {
          _startLocationUpdates();
          _checkMissedAssignments();
        }
      }
    } catch (e) {
      if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to sync status: $e')));
         setState(() => _isLoadingInitial = false);
      }
    }
  }

  StreamSubscription<ServiceStatus>? _serviceStatusStreamSubscription;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _wsLocationService?.stopTracking();
    _serviceStatusStreamSubscription?.cancel();
    _fcmForegroundSubscription?.cancel();
    super.dispose();
  }

  void _toggleOnline() async {
    if (_verificationStatus != 'VERIFIED') {
       ScaffoldMessenger.of(context).showSnackBar(
         const SnackBar(content: Text('You must be VERIFIED to go online.'))
       );
       return;
    }
    // Show confirmation dialog before changing status
    final confirmed = await _showToggleConfirmationDialog(_isOnline);
    if (confirmed != true || !mounted) return;

    setState(() => _isLoading = true);
    try {
      if (_isOnline) {
        await _goOffline();
      } else {
        await _goOnline();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: AppPallete.error));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Shows a professional confirmation card before going online or offline.
  Future<bool?> _showToggleConfirmationDialog(bool currentlyOnline) {
    final goingOnline = !currentlyOnline;

    final quotes = goingOnline
        ? [
            'Every second counts. Drive safe.',
            'You save lives. Thank you for showing up.',
            'Heroes don\'t wear capes — they drive ambulances.',
          ]
        : [
            'Rest well. You\'ve earned it.',
            'Every hero needs a break. See you soon.',
            'Thanks for your service today.',
          ];
    final quote = quotes[DateTime.now().second % quotes.length];

    return showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Confirm',
      barrierColor: Colors.black.withOpacity(0.6),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (ctx, anim, secondaryAnim) => const SizedBox.shrink(),
      transitionBuilder: (ctx, anim, secondaryAnim, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return ScaleTransition(
          scale: curved,
          child: FadeTransition(
            opacity: curved,
            child: Center(
              child: Material(
                color: Colors.transparent,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 28),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: goingOnline
                          ? Colors.green.withOpacity(0.35)
                          : Colors.red.withOpacity(0.35),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: (goingOnline ? Colors.green : Colors.red).withOpacity(0.18),
                        blurRadius: 40,
                        spreadRadius: 4,
                      ),
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 20,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Icon circle
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: goingOnline
                                  ? [Colors.green.shade400, Colors.green.shade800]
                                  : [Colors.red.shade400, Colors.red.shade800],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: Icon(
                            goingOnline ? Icons.power_settings_new : Icons.power_off_rounded,
                            color: Colors.white,
                            size: 36,
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Title
                        Text(
                          goingOnline ? 'Go Online?' : 'Go Offline?',
                          style: const TextStyle(
                            color: Color(0xFF1A1A1A),
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Subtitle
                        Text(
                          goingOnline
                              ? 'You\'ll start receiving emergency\nrequests immediately.'
                              : 'You\'ll stop receiving emergency\nrequests.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFF6B6B6B),
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Quote card
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: goingOnline
                                ? Colors.green.withOpacity(0.06)
                                : Colors.red.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: goingOnline
                                  ? Colors.green.withOpacity(0.2)
                                  : Colors.red.withOpacity(0.2),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.format_quote_rounded,
                                color: goingOnline ? Colors.green.shade600 : Colors.red.shade600,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  quote,
                                  style: const TextStyle(
                                    color: Color(0xFF555555),
                                    fontSize: 13,
                                    fontStyle: FontStyle.italic,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 28),

                        // Action buttons
                        Row(
                          children: [
                            // No button
                            Expanded(
                              child: TextButton(
                                onPressed: () => Navigator.of(ctx).pop(false),
                                style: TextButton.styleFrom(
                                  foregroundColor: const Color(0xFF555555),
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    side: const BorderSide(color: Color(0xFFDDDDDD)),
                                  ),
                                ),
                                child: const Text(
                                  'Not Now',
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Yes button
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () => Navigator.of(ctx).pop(true),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: goingOnline ? Colors.green.shade600 : Colors.red.shade600,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  elevation: 6,
                                  shadowColor: (goingOnline ? Colors.green : Colors.red).withOpacity(0.4),
                                ),
                                child: Text(
                                  goingOnline ? "Let's Go!" : 'Go Offline',
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _goOffline() async {
    if (_activeAssignment != null) {
       ScaffoldMessenger.of(context).showSnackBar(
         const SnackBar(content: Text('Finish active mission first!'))
       );
       return;
    }
    await ref.read(driverRepositoryProvider).endShift();
    _stopLocationUpdates();
    setState(() => _isOnline = false);
  }

  Future<void> _goOnline() async {
    // Flow required by product: confirmation -> internet/location validation -> online.
    final isReady = await _validateOnlinePrerequisites();
    if (!isReady) return;

    // Prime map position quickly so camera can zoom to driver within ~2s.
    final fastPosition = await _getQuickPosition();
    if (fastPosition != null && mounted) {
      setState(() => _currentPosition = fastPosition);
    }

    // 2. Start Shift — auto-detect ambulance assigned to this driver
    final ambulanceId = await ref.read(driverRepositoryProvider).getMyAmbulanceId();
    if (ambulanceId == null) {
      throw "No ambulance assigned to your account. Contact admin.";
    }
    await ref.read(driverRepositoryProvider).startShift(ambulanceId);
    setState(() => _isOnline = true);
    
    // 3. Start Streaming
    _startLocationUpdates();
    _checkMissedAssignments();
    _startServiceStatusListener();
  }

  Future<bool> _validateOnlinePrerequisites() async {
    final hasInternet = await _hasInternetConnection();
    if (!hasInternet) {
      if (!mounted) return false;
      await _showSimpleRequirementDialog(
        title: 'No Internet Connection',
        message:
            'You are offline. Please turn on mobile data or Wi-Fi, then try again.',
      );
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.deniedForever) {
      if (!mounted) return false;
      final openSettings = await _showSimpleRequirementDialog(
        title: 'Location Permission Needed',
        message:
            'Location permission is permanently denied. Enable Location permission from App Settings to go online.',
        actionText: 'Open App Settings',
      );
      if (openSettings == true) {
        await Geolocator.openAppSettings();
      }
      return false;
    }

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (!mounted) return false;
        await _showSimpleRequirementDialog(
          title: 'Location Permission Denied',
          message:
              'Please select "Allow while using the app" to go online and receive missions.',
        );
        return false;
      }
      if (permission == LocationPermission.deniedForever) {
        if (!mounted) return false;
        final openSettings = await _showSimpleRequirementDialog(
          title: 'Location Permission Needed',
          message:
              'Location permission is permanently denied. Enable it from App Settings to continue.',
          actionText: 'Open App Settings',
        );
        if (openSettings == true) {
          await Geolocator.openAppSettings();
        }
        return false;
      }
    }

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return false;
      final openLocation = await _showSimpleRequirementDialog(
        title: 'Turn On Location Service',
        message:
            'GPS is currently off. Tap "Turn On Location" and enable device location to go online.',
        actionText: 'Turn On Location',
      );

      if (openLocation == true) {
        await Geolocator.openLocationSettings();
        await Future.delayed(const Duration(milliseconds: 1200));
      }

      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location is still off. Please enable GPS and try again.'),
              backgroundColor: AppPallete.error,
            ),
          );
        }
        return false;
      }
    }

    return true;
  }

  Future<bool> _hasInternetConnection() async {
    try {
      final response = await Dio().get(
        'https://clients3.google.com/generate_204',
        options: Options(
          sendTimeout: const Duration(seconds: 3),
          receiveTimeout: const Duration(seconds: 3),
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      return response.statusCode != null && response.statusCode! < 400;
    } catch (_) {
      return false;
    }
  }

  Future<Position?> _getQuickPosition() async {
    try {
      final quickPosition = await Future.any<Position?>([
        Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
        ),
        Future<Position?>.delayed(const Duration(seconds: 2), () => null),
      ]);
      return quickPosition ?? Geolocator.getLastKnownPosition();
    } catch (_) {
      return Geolocator.getLastKnownPosition();
    }
  }

  Future<bool?> _showSimpleRequirementDialog({
    required String title,
    required String message,
    String actionText = 'OK',
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppPallete.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(actionText),
          ),
        ],
      ),
    );
  }

  Future<void> _checkMissedAssignments() async {
    try {
      final assignment = await ref.read(driverRepositoryProvider).getAssignedEmergency();
      if (assignment != null && mounted) {
        _handleAssignmentData(assignment);
      }
    } catch (e) {
      debugPrint("No missed assignments: $e");
    }
  }

  /// Handles assignment data on startup/resume.
  /// - If status is ASSIGNED  → show accept/reject dialog
  /// - If status is ACCEPTED  → restore active mission at the correct step
  ///
  /// IMPORTANT: The assignment `status` field is always "ACCEPTED" after the driver
  /// accepts — it never changes to AT_PATIENT or TO_HOSPITAL.  Those are *emergency*
  /// statuses on `assignmentData['emergency']['status']`.  We derive the UI step from
  /// there so the correct button (Arrive / Picked Up / Complete) is shown after restart.
  void _handleAssignmentData(Map<String, dynamic> assignmentData) {
    final statusStr = (assignmentData['status'] ?? '').toString();
    if (statusStr == 'ASSIGNED') {
      // Driver hasn't responded yet → show accept/reject dialog
      _showRequestDialog(assignmentData);
    } else if (statusStr == 'ACCEPTED') {
      // Derive the actual UI step from the emergency status
      final dynamic emergency = assignmentData['emergency'];
      final String emergencyStatus =
          (emergency is Map ? (emergency['status'] ?? '') : '').toString();

      final String missionStatus;
      if (emergencyStatus == 'AT_PATIENT') {
        missionStatus = 'AT_PATIENT';
      } else if (emergencyStatus == 'TO_HOSPITAL') {
        missionStatus = 'TO_HOSPITAL';
      } else {
        // IN_PROGRESS (en route to patient) — treat the same as freshly ACCEPTED
        missionStatus = 'ACCEPTED';
      }

      setState(() {
        // Override the copy's 'status' so active_mission_view.dart drives the
        // correct step button without needing its own emergency-status awareness.
        _activeAssignment = Map<String, dynamic>.from(assignmentData)
          ..['status'] = missionStatus;
        _missionStatus = missionStatus;
      });
    }
    // REJECTED / COMPLETED / other states → nothing to restore
  }

  void _startServiceStatusListener() {
    _serviceStatusStreamSubscription?.cancel();
    _serviceStatusStreamSubscription = Geolocator.getServiceStatusStream().listen((status) {
      if (status == ServiceStatus.disabled && _isOnline) {
        debugPrint("⚠️ Location service disabled! Handling automatically.");
        if (_activeAssignment != null) {
          // Active mission running — warn driver and force cancel + go offline
          _handleGpsTurnedOffDuringMission();
        } else {
          // Just go offline silently
          _goOffline().then((_) {
            if (mounted) {
               ScaffoldMessenger.of(context).showSnackBar(
                 const SnackBar(
                   content: Text('⚠️ You went offline because Location Service was disabled.'),
                   backgroundColor: AppPallete.error,
                   duration: Duration(seconds: 5),
                 )
               );
            }
          });
        }
      }
    });
  }

  /// Driver turned off GPS while on an active mission.
  /// Show a blocking dialog — driver must either re-enable GPS or cancel the mission.
  void _handleGpsTurnedOffDuringMission() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        icon: const Icon(Icons.location_off_rounded, color: Colors.red, size: 50),
        title: const Text('GPS Disabled'),
        content: const Text(
          'You turned off GPS during an active mission. '
          'You must keep GPS on to navigate to the patient. '
          'Re-enable GPS to continue, or cancel the mission.',
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
              _cancelActiveMission().then((_) => _goOffline());
            },
            child: const Text('Cancel Mission & Go Offline'),
          ),
        ],
      ),
    );
  }

  void _startLocationUpdates() {
    _wsLocationService?.stopTracking();

    // Use AppConfig.wsBaseUrl which automatically strips /api from the REST base URL
    // so that WsLocationService can correctly append /ws for STOMP connections.
    _wsLocationService = WsLocationService(
      backendUrl: AppConfig.wsBaseUrl,
      onAssignmentUpdate: (message) {
         if (!mounted) return;
         try {
           final data = json.decode(message);
           final assigned = data['assigned'] ?? false;
           
           if (assigned == true) {
             if (_activeAssignment != null) return;
             final emergencyData = data['emergency'];
             final assignment = {
               'emergency': emergencyData,
               'status': 'ASSIGNED',
             };
             _showRequestDialog(assignment);
           } else {
             final reason = (data['reason'] as String?) ?? 'Mission Cancelled';
             // Pop dialog if it's showing
             if (Navigator.of(context).canPop()) {
                 Navigator.of(context).pop();
             }
             final hadActiveMission = _activeAssignment != null;
             setState(() {
                _activeAssignment = null;
                _missionStatus = 'IDLE';
                _isOnline = true;
             });
             // Show a prominent dialog if an active mission was cancelled
             if (hadActiveMission) {
               _showMissionCancelledDialog(reason);
             } else {
               ScaffoldMessenger.of(context).showSnackBar(
                 SnackBar(content: Text(reason))
               );
             }
           }
         } catch (e) {
           debugPrint("Error parsing assignment STOMP payload: $e");
         }
      },
      // Called on every GPS position — updates the driver marker on the mission map
      onPositionUpdate: (position) {
        if (mounted) {
          setState(() => _currentPosition = position);
        }
        // Location is sent to the backend via STOMP inside WsLocationService —
        // no REST HTTP call needed here.
      },
      // Called on every location send (GPS movement + 30-second stationary timer).
      // Calls REST PUT /api/driver/location as a parallel path alongside STOMP so
      // that the currently-deployed backend (which has no STOMP /app/driver.location
      // handler yet) still receives heartbeat updates and keeps lastHeartbeat fresh.
      onLocationSend: (lat, lng) {
        ref.read(driverRepositoryProvider).updateLocation(lat, lng);
      },
    );

    _wsLocationService!.startTracking();
  }

  void _stopLocationUpdates() {
    _wsLocationService?.stopTracking();
    _wsLocationService = null;
    _serviceStatusStreamSubscription?.cancel();
  }

  void _showRequestDialog(Map<String, dynamic> assignment) {
    final emergencyData = assignment['emergency'] as Map<String, dynamic>? ?? {};
    final String type = (emergencyData['type'] ?? 'EMERGENCY').toString();
    final String severity = (emergencyData['severity'] ?? 'HIGH').toString();
    final int emergencyId = emergencyData['id'] as int? ?? 0;
    if (_activeAssignment != null) return;
    if (emergencyId != 0 && _pendingAssignmentEmergencyId == emergencyId) return;
    _pendingAssignmentEmergencyId = emergencyId;
    final String? patientName = emergencyData['patientName']?.toString();
    final String? patientPhone = emergencyData['patientPhone']?.toString();

    final Color severityColor = severity == 'CRITICAL'
        ? const Color(0xFFD32F2F)
        : severity == 'HIGH'
            ? const Color(0xFFF57C00)
            : const Color(0xFF388E3C);

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Emergency Alert',
      barrierColor: Colors.black.withOpacity(0.55),
      transitionDuration: const Duration(milliseconds: 350),
      pageBuilder: (ctx, a1, a2) => const SizedBox.shrink(),
      transitionBuilder: (ctx, a1, a2, child) {
        final curved = CurvedAnimation(parent: a1, curve: Curves.easeOutBack);
        return ScaleTransition(
          scale: curved,
          child: FadeTransition(
            opacity: CurvedAnimation(parent: a1, curve: Curves.easeOut),
            child: Center(
              child: Material(
                color: Colors.transparent,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withOpacity(0.2),
                        blurRadius: 40,
                        spreadRadius: 4,
                      ),
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 20,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ── Red header banner ──────────────────────────
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 24),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFFD32F2F), Color(0xFFB71C1C)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.emergency_rounded, color: Colors.white, size: 26),
                            ),
                            const SizedBox(width: 14),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'INCOMING EMERGENCY',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                Text(
                                  type,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.85),
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                            const Spacer(),
                            // Severity chip
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: severityColor,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                severity,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // ── Body ──────────────────────────────────────
                      Padding(
                        padding: const EdgeInsets.all(22),
                        child: Column(
                          children: [
                            // Patient info row
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8F8F8),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: const Color(0xFFEEEEEE)),
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 26,
                                    backgroundColor: const Color(0xFFFFEBEE),
                                    child: Icon(Icons.person_rounded,
                                        color: const Color(0xFFD32F2F), size: 28),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          patientName ?? 'Patient',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 16,
                                            color: Color(0xFF1A1A1A),
                                          ),
                                        ),
                                        if (patientPhone != null) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            patientPhone,
                                            style: const TextStyle(
                                              color: Color(0xFF6B6B6B),
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  // Direct call button
                                  if (patientPhone != null)
                                    GestureDetector(
                                      onTap: () async {
                                        final uri = Uri(scheme: 'tel', path: patientPhone);
                                        if (await canLaunchUrl(uri)) {
                                          await launchUrl(uri);
                                        }
                                      },
                                      child: Container(
                                        width: 46,
                                        height: 46,
                                        decoration: BoxDecoration(
                                          gradient: const LinearGradient(
                                            colors: [Color(0xFF4CAF50), Color(0xFF2E7D32)],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          ),
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.green.withOpacity(0.3),
                                              blurRadius: 12,
                                              offset: const Offset(0, 4),
                                            ),
                                          ],
                                        ),
                                        child: const Icon(Icons.call_rounded,
                                            color: Colors.white, size: 22),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),

                            // Info chips row
                            Row(
                              children: [
                                _buildChip(Icons.medical_services_rounded, type, const Color(0xFFE3F2FD), const Color(0xFF1565C0)),
                                const SizedBox(width: 10),
                                _buildChip(Icons.location_on_rounded, 'Nearby', const Color(0xFFF3E5F5), const Color(0xFF7B1FA2)),
                              ],
                            ),
                            const SizedBox(height: 18),

                            // Confirm text
                            const Text(
                              'Do you accept this emergency request?',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Color(0xFF444444),
                                fontSize: 14,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 20),

                            // Action buttons
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () async {
                                      Navigator.pop(ctx);
                                      await _rejectRequest(emergencyId);
                                    },
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFF888888),
                                      side: const BorderSide(color: Color(0xFFDDDDDD)),
                                      padding: const EdgeInsets.symmetric(vertical: 15),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                    child: const Text('Decline',
                                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  flex: 2,
                                  child: ElevatedButton(
                                    onPressed: () async {
                                      Navigator.pop(ctx);
                                      await _acceptRequest(assignment);
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF2E7D32),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 15),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      elevation: 4,
                                      shadowColor: Colors.green.withOpacity(0.4),
                                    ),
                                    child: const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.check_circle_outline_rounded, size: 20),
                                        SizedBox(width: 8),
                                        Text('Accept Mission',
                                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ).then((_) {
      if (_pendingAssignmentEmergencyId == emergencyId) {
        _pendingAssignmentEmergencyId = null;
      }
    });
  }

  Widget _buildChip(IconData icon, String label, Color bg, Color fg) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: fg, size: 16),
            const SizedBox(width: 6),
            Flexible(
              child: Text(label,
                style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }


  Future<void> _acceptRequest(Map<String, dynamic> assignment) async {
    if (_isAssignmentDecisionInProgress) return;
    _isAssignmentDecisionInProgress = true;
    try {
      int emergencyId = assignment['emergency']['id'];
      await ref.read(driverRepositoryProvider).acceptEmergency(emergencyId);
      if (mounted) {
        setState(() {
          // Clone map and set status so ActiveMissionView shows correct button label
          _activeAssignment = Map<String, dynamic>.from(assignment)..['status'] = 'ACCEPTED';
          _missionStatus = 'ACCEPTED';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mission Started! Heading to Patient.'), backgroundColor: AppPallete.success)
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      _isAssignmentDecisionInProgress = false;
      _pendingAssignmentEmergencyId = null;
    }
  }
  
  Future<void> _rejectRequest(int emergencyId) async {
    if (_isAssignmentDecisionInProgress) return;
    _isAssignmentDecisionInProgress = true;
    try {
      await ref.read(driverRepositoryProvider).rejectEmergency(emergencyId);
    } catch (e) {
       if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      _isAssignmentDecisionInProgress = false;
      _pendingAssignmentEmergencyId = null;
    }
  }

  Future<void> _markArrivedAtPatient() async {
    if (_activeAssignment == null) return;
    setState(() => _isLoading = true);
    try {
      int emergencyId = _activeAssignment!['emergency']['id'];
      await ref.read(driverRepositoryProvider).markArrivedAtPatient(emergencyId);
      if (mounted) {
        setState(() {
          _missionStatus = 'AT_PATIENT';
          _activeAssignment = Map<String, dynamic>.from(_activeAssignment!)..['status'] = 'AT_PATIENT';
        });
      }
    } on Exception catch (e) {
      final msg = e.toString();
      // 409 means server already has AT_PATIENT — treat as success, sync local state
      if (msg.contains('409') || msg.contains('AT_PATIENT')) {
        if (mounted) {
          setState(() {
            _missionStatus = 'AT_PATIENT';
            _activeAssignment = Map<String, dynamic>.from(_activeAssignment!)..['status'] = 'AT_PATIENT';
          });
        }
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _markExamplePatientPickup() async {
    if (_activeAssignment == null) return;
    
    if (_currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Waiting for GPS signal. Cannot update status.'))
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      int emergencyId = _activeAssignment!['emergency']['id'];
      
      final response = await ref.read(driverRepositoryProvider).markPatientPickedUp(
        emergencyId,
        _currentPosition!.latitude,
        _currentPosition!.longitude,
      );

      // Capture hospital data from the response so the map can route to it
      final hospital = response['hospital'] as Map<String, dynamic>?;

      if (mounted) {
        setState(() {
          _missionStatus = 'TO_HOSPITAL';
          _activeAssignment = Map<String, dynamic>.from(_activeAssignment!)
            ..['status'] = 'TO_HOSPITAL'
            ..['hospital'] = hospital; // driver map uses this to route to hospital
        });
      }
    } on Exception catch (e) {
      final msg = e.toString();
      // 409: server already in TO_HOSPITAL — sync local state silently
      if (msg.contains('409') || msg.contains('TO_HOSPITAL')) {
        if (mounted) setState(() {
          _missionStatus = 'TO_HOSPITAL';
          _activeAssignment = Map<String, dynamic>.from(_activeAssignment!)..['status'] = 'TO_HOSPITAL';
        });
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _markMissionComplete() async {
    if (_activeAssignment == null) return;

    if (_currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Waiting for GPS signal. Cannot complete mission.'))
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      int emergencyId = _activeAssignment!['emergency']['id'];
      
      // Use live GPS coordinates of the driver instead of hardcoded coordinates
      await ref.read(driverRepositoryProvider).completeMission(
        emergencyId, 
        _currentPosition!.latitude, 
        _currentPosition!.longitude
      );
      
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppPallete.lightGrey,
          title: const Icon(Icons.check_circle, color: AppPallete.success, size: 60),
          content: const Text(
            "Mission Completed Successfully!\nGood job.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 18),
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                setState(() {
                  _activeAssignment = null;
                  _missionStatus = 'IDLE';
                });
                _checkMissedAssignments();
              },
              child: const Text('Back to Dashboard'),
            )
          ],
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _handleLogout() async {
     final prefs = await SharedPreferences.getInstance();
     await prefs.clear();
     if (mounted) context.go('/login');
  }

  /// Shows a blocking dialog when the current mission is cancelled (by admin or patient).
  /// Driver is returned to the dashboard in a ready/online state.
  void _showMissionCancelledDialog(String reason) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.cancel_outlined, color: Colors.red, size: 56),
        title: const Text('Mission Cancelled'),
        content: Text(
          reason.isNotEmpty
              ? reason
              : 'This emergency has been cancelled. You are now available for new missions.',
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppPallete.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              // Check for any newly missed assignments after returning to dashboard
              _checkMissedAssignments();
            },
            child: const Text('Back to Dashboard'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleStatusUpdate() async {
    if (_isLoading) return; // guard against double-tap
    if (_missionStatus == 'ACCEPTED') {
      await _markArrivedAtPatient();
    } else if (_missionStatus == 'AT_PATIENT') {
      await _markExamplePatientPickup(); // "Heading to Hospital"
    } else if (_missionStatus == 'TO_HOSPITAL') {
      await _markMissionComplete();
    }
  }

  Future<void> _cancelActiveMission() async {
    if (_activeAssignment == null) return;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Cancel Mission?"),
          content: const Text("Are you sure you want to cancel this mission? This may affect your rating."),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("No")),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Yes, Cancel", style: TextStyle(color: Colors.red))
            ),
          ],
        )
     );

    if (confirmed != true) return;

    setState(() => _isLoading = true);
    try {
      final int emergencyId = _activeAssignment!['emergency']['id'];
      await ref.read(driverRepositoryProvider).cancelMission(emergencyId);
      setState(() {
        _activeAssignment = null;
        _missionStatus = 'IDLE';
      });
      _checkMissedAssignments();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to cancel mission: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingInitial) {
       return const Scaffold(
         backgroundColor: Color(0xFF121212),
         body: Center(child: CircularProgressIndicator(color: AppPallete.primary)),
       );
    }

    return Scaffold(
      extendBodyBehindAppBar: true, 
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppTheme.backgroundGradient,
        ),
        child: SafeArea(
          child: Column(
            children: [
               DriverAppBar(onLogout: _handleLogout),
               
               Expanded(
                 child: _activeAssignment != null 
                     ? ActiveMissionView(
                         missionData: _activeAssignment!,
                         currentDriverPosition: _currentPosition, // Live GPS position
                         onStatusUpdate: _handleStatusUpdate,
                         onCancel: _cancelActiveMission,
                         isLoading: _isLoading,
                       )
                     : (_verificationStatus == 'VERIFIED' 
                         ? DriverDashboardView(
                             isOnline: _isOnline,
                             isLoading: _isLoading,
                             onToggleOnline: _toggleOnline,
                             currentPosition: _currentPosition,
                           ) 
                         : VerificationPendingView(
                           verificationStatus: _verificationStatus ?? 'PENDING',
                           hasUploadedDocument: _hasUploadedVerificationDocument,
                           onStatusRefresh: _fetchInitialStatus,
                           )),
               ),
               
               const DriverBottomNav(),
            ],
          ),
        ),
      ),
    );
  }
}
