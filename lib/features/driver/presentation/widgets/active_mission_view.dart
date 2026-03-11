import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/config/app_config.dart';
import '../../../location/data/map_repository.dart';

class ActiveMissionView extends ConsumerStatefulWidget {
  final Map<String, dynamic> missionData;
  final Position? currentDriverPosition; // Live GPS from WsLocationService
  final VoidCallback onStatusUpdate;
  final VoidCallback onCancel;
  final bool isLoading;

  const ActiveMissionView({
    super.key,
    required this.missionData,
    this.currentDriverPosition,
    required this.onStatusUpdate,
    required this.onCancel,
    this.isLoading = false,
  });

  @override
  ConsumerState<ActiveMissionView> createState() => _ActiveMissionViewState();
}

class _ActiveMissionViewState extends ConsumerState<ActiveMissionView> {
  final Completer<GoogleMapController> _controller = Completer();
  Set<Polyline> _polylines = {};
  Set<Marker> _markers = {};
  Timer? _debounceTimer;
  LatLng? _lastRouteDest;
  bool _isUpdatingMap = false;

  // Default to New Delhi
  static const CameraPosition _kGooglePlex = CameraPosition(
    target: LatLng(28.6139, 77.2090),
    zoom: 14.4746,
  );

  @override
  void initState() {
    super.initState();
    _updateMap();
  }

  @override
  void didUpdateWidget(covariant ActiveMissionView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-draw map whenever driver GPS moves or mission step changes
    if (widget.currentDriverPosition != oldWidget.currentDriverPosition ||
        widget.missionData['status'] != oldWidget.missionData['status']) {
      _updateMap();
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  double _metersApart(LatLng a, LatLng b) {
    const r = 6371000.0;
    final dLat = (b.latitude - a.latitude) * pi / 180;
    final dLon = (b.longitude - a.longitude) * pi / 180;
    final sq = sin(dLat / 2) * sin(dLat / 2) +
        cos(a.latitude * pi / 180) * cos(b.latitude * pi / 180) *
        sin(dLon / 2) * sin(dLon / 2);
    return r * 2 * atan2(sqrt(sq), sqrt(1 - sq));
  }

  Future<void> _updateMap() async {
    if (_isUpdatingMap) return;
    _isUpdatingMap = true;
    try {
      await _doUpdateMap();
    } finally {
      _isUpdatingMap = false;
    }
  }

  Future<void> _doUpdateMap() async {
    // Driver location — use live GPS if available, fall back to New Delhi
    LatLng driverLoc;
    if (widget.currentDriverPosition != null) {
      driverLoc = LatLng(
        widget.currentDriverPosition!.latitude,
        widget.currentDriverPosition!.longitude,
      );
    } else {
      driverLoc = const LatLng(28.6139, 77.2090); // Fallback until GPS is ready
    }
    // Patient Location from missionData
    // Structure: missionData = { "emergency": { "latitude": X, "longitude": Y, ... }, "status": "ASSIGNED" }
    // Also supports flat structure for backward compat
    LatLng patientLoc = const LatLng(28.6200, 77.2100);

    // Try nested emergency object first (standard API structure)
    final emergencyMap = widget.missionData['emergency'] as Map<String, dynamic>?;
    final rawLat = emergencyMap?['latitude'] ?? widget.missionData['latitude'];
    final rawLng = emergencyMap?['longitude'] ?? widget.missionData['longitude'];

    if (rawLat != null && rawLng != null) {
       patientLoc = LatLng(
         double.tryParse(rawLat.toString()) ?? 28.6200,
         double.tryParse(rawLng.toString()) ?? 77.2100,
       );
    }

    // Hospital — available after markPatientPickedUp (TO_HOSPITAL phase).
    // Two sources:
    //   1. Freshly stored from markPatientPickedUp response: missionData['hospital']
    //   2. App restart — comes from the assignment entity:    missionData['assignment']['destinationHospital']
    LatLng? hospitalLoc;
    String? hospitalName;
    Map<String, dynamic>? hospitalMap =
        widget.missionData['hospital'] as Map<String, dynamic>?;
    if (hospitalMap == null) {
      final assignmentEntity =
          widget.missionData['assignment'] as Map<String, dynamic>?;
      hospitalMap =
          assignmentEntity?['destinationHospital'] as Map<String, dynamic>?;
    }
    if (hospitalMap != null) {
      final hLat = hospitalMap['latitude'];
      final hLng = hospitalMap['longitude'];
      if (hLat != null && hLng != null) {
        hospitalLoc = LatLng(
          double.tryParse(hLat.toString()) ?? patientLoc.latitude,
          double.tryParse(hLng.toString()) ?? patientLoc.longitude,
        );
        hospitalName = hospitalMap['name']?.toString();
      }
    }

    final status = widget.missionData['status'] ?? 'ASSIGNED';
    // During TO_HOSPITAL, route and camera should focus on hospital, otherwise patient
    final LatLng routeDestination =
        (status == 'TO_HOSPITAL' && hospitalLoc != null) ? hospitalLoc : patientLoc;

    // 2. Update Markers
    setState(() {
      _markers = {
        Marker(
          markerId: const MarkerId('driver'),
          position: driverLoc,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: const InfoWindow(title: 'You'),
        ),
        Marker(
          markerId: const MarkerId('patient'),
          position: patientLoc,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: const InfoWindow(title: 'Patient Location'),
        ),
        if (hospitalLoc != null)
          Marker(
            markerId: const MarkerId('hospital'),
            position: hospitalLoc,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
            infoWindow: InfoWindow(title: hospitalName ?? 'Hospital'),
          ),
      };
    });

    // 3. Keep Camera Focused
    final GoogleMapController controller = await _controller.future;
    final List<LatLng> boundsPoints = [
      driverLoc,
      routeDestination,
      if (hospitalLoc != null && status == 'TO_HOSPITAL') hospitalLoc,
    ];
    LatLngBounds bounds = _boundsFromLatLngList(boundsPoints);
    controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 100));

    // Route fetch — debounced + cached.
    // Only calls the Directions API when destination moves > 30 m.
    final bool destChanged = _lastRouteDest == null ||
        _metersApart(_lastRouteDest!, routeDestination) > 30;
    if (!destChanged) return;

    _lastRouteDest = routeDestination;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 700), () async {
      try {
        final route = await ref.read(mapRepositoryProvider).getRouteCoordinates(
          driverLoc,
          routeDestination,
          AppConfig.googleMapsApiKey,
        );
        if (mounted) {
          setState(() {
            _polylines = {
              Polyline(
                polylineId: const PolylineId('route'),
                points: route.isNotEmpty ? route : [driverLoc, routeDestination],
                color: Colors.blue,
                width: 5,
                geodesic: true,
              ),
            };
          });
        }
      } catch (e) {
        debugPrint('Route fetch error: $e');
        if (mounted) {
          setState(() {
            _polylines = {
              Polyline(
                polylineId: const PolylineId('route'),
                points: [driverLoc, routeDestination],
                color: Colors.blue.withOpacity(0.5),
                width: 4,
                geodesic: true,
                patterns: [PatternItem.dash(10), PatternItem.gap(8)],
              )
            };
          });
        }
      }
    });
  }

  LatLngBounds _boundsFromLatLngList(List<LatLng> list) {
    double? x0, x1, y0, y1;
    for (LatLng latLng in list) {
      if (x0 == null) {
        x0 = x1 = latLng.latitude;
        y0 = y1 = latLng.longitude;
      } else {
        if (latLng.latitude > x1!) x1 = latLng.latitude;
        if (latLng.latitude < x0) x0 = latLng.latitude;
        if (latLng.longitude > y1!) y1 = latLng.longitude;
        if (latLng.longitude < y0!) y0 = latLng.longitude;
      }
    }
    return LatLngBounds(northeast: LatLng(x1!, y1!), southwest: LatLng(x0!, y0!));
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.missionData['status'] ?? 'ASSIGNED';

    // Logic for next action button
    String nextActionText = "Accept Mission";
    Color nextActionColor = Colors.green;
    
    if (status == 'ASSIGNED') {
      nextActionText = "Accept Mission";
    } else if (status == 'ACCEPTED') {
      nextActionText = "Arrived at Location";
    } else if (status == 'AT_PATIENT') {
       nextActionText = "Heading to Hospital";
    } else if (status == 'TO_HOSPITAL') {
       nextActionText = "Complete Mission";
    } else {
       nextActionText = "Mission Completed";
    }

    int stepIdx = 0;
    if (status == 'ACCEPTED') stepIdx = 1;
    else if (status == 'AT_PATIENT') stepIdx = 2;
    else if (status == 'TO_HOSPITAL') stepIdx = 3;
    else if (status == 'COMPLETED') stepIdx = 4;

    // Determine current navigation destination for the external Maps button
    LatLng? _navDestination;
    final emergencyMap = widget.missionData['emergency'] as Map<String, dynamic>?;
    final rawLat = emergencyMap?['latitude'] ?? widget.missionData['latitude'];
    final rawLng = emergencyMap?['longitude'] ?? widget.missionData['longitude'];
    if (rawLat != null && rawLng != null) {
      _navDestination = LatLng(
        double.tryParse(rawLat.toString()) ?? 28.6200,
        double.tryParse(rawLng.toString()) ?? 77.2100,
      );
    }
    if (status == 'TO_HOSPITAL') {
      Map<String, dynamic>? hospitalMap =
          widget.missionData['hospital'] as Map<String, dynamic>?;
      if (hospitalMap == null) {
        final assignmentEntity =
            widget.missionData['assignment'] as Map<String, dynamic>?;
        hospitalMap =
            assignmentEntity?['destinationHospital'] as Map<String, dynamic>?;
      }
      if (hospitalMap != null) {
        final hLat = hospitalMap['latitude'];
        final hLng = hospitalMap['longitude'];
        if (hLat != null && hLng != null) {
          _navDestination = LatLng(
            double.tryParse(hLat.toString()) ?? _navDestination?.latitude ?? 28.6200,
            double.tryParse(hLng.toString()) ?? _navDestination?.longitude ?? 77.2090,
          );
        }
      }
    }

    return Stack(
      children: [
        // 1. Full Screen Map (RepaintBoundary isolates map from bottom sheet rebuilds)
        RepaintBoundary(
          child: SizedBox(
           height: MediaQuery.of(context).size.height,
           width: MediaQuery.of(context).size.width,
           child: GoogleMap(
              mapType: MapType.normal,
              initialCameraPosition: _kGooglePlex,
              myLocationEnabled: true,
              myLocationButtonEnabled: false, // Cleaner UI
              zoomControlsEnabled: false, // Use gestures
              polylines: _polylines,
              markers: _markers,
              onMapCreated: (GoogleMapController controller) {
                _controller.complete(controller);
                _updateMap();
              },
            ),
          ),
        ),

        // 2. Action Bottom Sheet
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(30),
                topRight: Radius.circular(30),
              ),
              boxShadow: [
                 BoxShadow(
                   color: Colors.black.withOpacity(0.2),
                   blurRadius: 20,
                   spreadRadius: 5,
                   offset: const Offset(0, -5),
                 )
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Active Mission",
                      style: GoogleFonts.poppins(
                         fontSize: 20,
                         fontWeight: FontWeight.bold,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.amber),
                      ),
                      child: Text(
                        status,
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.bold,
                          color: Colors.amber[800],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildStepProgress(stepIdx),
                const SizedBox(height: 20),

                // Patient Info
                Row(
                  children: [
                    const CircleAvatar(
                      radius: 24,
                      backgroundColor: Color(0xFFFFEBEE),
                      child: Icon(Icons.person_rounded, color: Color(0xFFD32F2F), size: 26),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (emergencyMap?['patientName'] ?? 'Patient').toString(),
                            style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Builder(builder: (context) {
                            // Real-time distance from driver to current destination
                            final pos = widget.currentDriverPosition;
                            String distText = 'Locating…';
                            if (pos != null) {
                              final dest = _navDestination;
                              if (dest != null) {
                                final metres = _metersApart(
                                  LatLng(pos.latitude, pos.longitude),
                                  dest,
                                );
                                if (metres < 1000) {
                                  distText = '${metres.round()} m away';
                                } else {
                                  distText = '${(metres / 1000).toStringAsFixed(1)} km away';
                                }
                              }
                            }
                            return Text(
                              distText,
                              style: GoogleFonts.inter(color: Colors.grey[600], fontSize: 13),
                            );
                          }),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Call patient button
                    Builder(builder: (context) {
                      final phone = emergencyMap?['patientPhone']?.toString();
                      if (phone == null) return const SizedBox.shrink();
                      return GestureDetector(
                        onTap: () async {
                          final uri = Uri(scheme: 'tel', path: phone);
                          if (await canLaunchUrl(uri)) await launchUrl(uri);
                        },
                        child: Container(
                          width: 42,
                          height: 42,
                          margin: const EdgeInsets.only(right: 8),
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
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: const Icon(Icons.call_rounded, color: Colors.white, size: 20),
                        ),
                      );
                    }),
                    // Navigation Button — opens Google Maps to current destination
                    CircleAvatar(
                      backgroundColor: Colors.blue,
                      child: IconButton(
                        icon: const Icon(Icons.navigation, color: Colors.white),
                        onPressed: _navDestination == null ? null : () async {
                          // Safe: ternary above guarantees non-null here
                          final dest = _navDestination!;
                          final lat = dest.latitude;
                          final lng = dest.longitude;
                          // Try Google Maps native app first, fall back to browser
                          final nativeUri = Uri.parse(
                              'google.navigation:q=$lat,$lng&mode=d');
                          final webUri = Uri.parse(
                              'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving');
                          if (await canLaunchUrl(nativeUri)) {
                            await launchUrl(nativeUri);
                          } else {
                            await launchUrl(webUri,
                                mode: LaunchMode.externalApplication);
                          }
                        },
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 30),
                
                // Primary Action Button
                ElevatedButton(
                  onPressed: widget.isLoading || status == 'COMPLETED' ? null : widget.onStatusUpdate,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: nextActionColor,
                    disabledBackgroundColor: nextActionColor.withOpacity(0.6),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    elevation: 5,
                  ),
                  child: widget.isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : Text(
                          nextActionText,
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                            color: Colors.white,
                          ),
                        ),
                ),
                
                // Cancel removed — driver must complete the mission once accepted
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStepProgress(int stepIdx) {
    const labels = ['Assigned', 'En Route', 'On Site', 'Hospital', 'Done'];
    const completedColor = Color(0xFF1565C0);

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(5, (i) {
            final bool done = i < stepIdx;
            final bool active = i == stepIdx;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: active ? 26 : 10,
                  height: 10,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(5),
                    color: done
                        ? completedColor
                        : active
                            ? Colors.green
                            : Colors.grey[300],
                  ),
                ),
                if (i < 4)
                  Container(
                    width: 14,
                    height: 2,
                    color: done ? completedColor : Colors.grey[300],
                  ),
              ],
            );
          }),
        ),
        const SizedBox(height: 6),
        Text(
          labels[stepIdx.clamp(0, 4)],
          style: const TextStyle(
            fontSize: 11,
            color: Colors.green,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}
