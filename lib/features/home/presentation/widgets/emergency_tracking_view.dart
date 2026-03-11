import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/theme/app_pallete.dart';
import '../../../location/data/map_repository.dart';

class EmergencyTrackingView extends ConsumerStatefulWidget {
  final Map<String, dynamic> trackingData;
  final VoidCallback onCancel;

  const EmergencyTrackingView({
    super.key,
    required this.trackingData,
    required this.onCancel,
  });

  @override
  ConsumerState<EmergencyTrackingView> createState() => _EmergencyTrackingViewState();
}

class _EmergencyTrackingViewState extends ConsumerState<EmergencyTrackingView> {
  final Completer<GoogleMapController> _controller = Completer();
  Set<Polyline> _polylines = {};
  Set<Marker> _markers = {};
  Timer? _debounceTimer;
  LatLng? _lastRouteDest;
  // Guard to prevent concurrent map update calls (each GPS tick fires didUpdateWidget)
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
  void didUpdateWidget(covariant EmergencyTrackingView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trackingData != oldWidget.trackingData) {
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
    if (_isUpdatingMap) return; // skip if already processing
    _isUpdatingMap = true;
    try {
      await _doUpdateMap();
    } finally {
      _isUpdatingMap = false;
    }
  }

  Future<void> _doUpdateMap() async {
    // 1. Extract Locations from trackingData
    // Backend sends: patientLat, patientLng, driverLat, driverLng

    // Patient location (where the emergency was created)
    LatLng patientLoc = const LatLng(28.6139, 77.2090); // Default fallback
    if (widget.trackingData['patientLat'] != null && widget.trackingData['patientLng'] != null) {
      patientLoc = LatLng(
        double.tryParse(widget.trackingData['patientLat'].toString()) ?? 28.6139,
        double.tryParse(widget.trackingData['patientLng'].toString()) ?? 77.2090,
      );
    }

    // Driver location (live GPS from driver session)
    LatLng driverLoc = LatLng(
      patientLoc.latitude + 0.003,  // ~300m offset as fallback until GPS arrives
      patientLoc.longitude + 0.003,
    );
    if (widget.trackingData['driverLat'] != null && widget.trackingData['driverLng'] != null) {
      driverLoc = LatLng(
        double.tryParse(widget.trackingData['driverLat'].toString()) ?? patientLoc.latitude + 0.003,
        double.tryParse(widget.trackingData['driverLng'].toString()) ?? patientLoc.longitude + 0.003,
      );
    }

    // Hospital location — only present once patient is picked up (TO_HOSPITAL phase)
    LatLng? hospitalLoc;
    if (widget.trackingData['hospitalLat'] != null && widget.trackingData['hospitalLng'] != null) {
      hospitalLoc = LatLng(
        double.tryParse(widget.trackingData['hospitalLat'].toString()) ?? patientLoc.latitude,
        double.tryParse(widget.trackingData['hospitalLng'].toString()) ?? patientLoc.longitude,
      );
    }

    // In TO_HOSPITAL phase route ambulance → hospital; otherwise ambulance → patient
    final LatLng routeDestination =
        (widget.trackingData['status'] == 'TO_HOSPITAL' && hospitalLoc != null)
            ? hospitalLoc
            : patientLoc;

    // 2. Update Markers
    setState(() {
      _markers = {
        Marker(
          markerId: const MarkerId('patient'),
          position: patientLoc,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: const InfoWindow(title: 'Your Location'),
        ),
        Marker(
          markerId: const MarkerId('driver'),
          position: driverLoc,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: const InfoWindow(title: 'Ambulance'),
        ),
        if (hospitalLoc != null)
          Marker(
            markerId: const MarkerId('hospital'),
            position: hospitalLoc,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
            infoWindow: InfoWindow(
              title: widget.trackingData['hospitalName']?.toString() ?? 'Hospital',
            ),
          ),
      };
    });

    // 3. Keep Camera Focused
    final GoogleMapController controller = await _controller.future;
    final List<LatLng> boundsPoints = [patientLoc, driverLoc, if (hospitalLoc != null) hospitalLoc];
    LatLngBounds bounds = _boundsFromLatLngList(boundsPoints);
    controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 100)); // 100 padding

    // Route fetch — debounced + cached.
    // Only calls the Directions API when the destination moves > 30 m,
    // preventing a new HTTP request on every GPS heartbeat (every 3–5 s).
    const activeStatuses = ['DISPATCHED', 'IN_PROGRESS', 'AT_PATIENT', 'TO_HOSPITAL'];
    if (!activeStatuses.contains(widget.trackingData['status'])) return;

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
    // Map Backend Status to UI Steps
    final status = widget.trackingData['status'];
    final eta = widget.trackingData['etaMinutes'] ?? '--';
    final ambulance = widget.trackingData['ambulanceCode'] ?? 'Unknown';
    final distanceKm = (widget.trackingData['distanceKm'] as num?)?.toDouble();

    // 0: Assigned, 1: Accepted, 2: At Patient, 3: To Hospital, 4: Completed
    int currentStep = 0;
    if (status == 'DISPATCHED') currentStep = 0;
    else if (status == 'IN_PROGRESS') currentStep = 1;
    else if (status == 'AT_PATIENT') currentStep = 2;
    else if (status == 'TO_HOSPITAL') currentStep = 3;
    else if (status == 'COMPLETED') currentStep = 4;

    return Stack(
      children: [
        // 1. Full Screen Map (RepaintBoundary isolates map repaints from sheet rebuilds)
        RepaintBoundary(
          child: SizedBox(
           height: MediaQuery.of(context).size.height,
           width: MediaQuery.of(context).size.width,
           child: GoogleMap(
              mapType: MapType.normal,
              initialCameraPosition: _kGooglePlex,
              myLocationEnabled: true, // Show blue dot for self
              myLocationButtonEnabled: false, // Hide default button, we can add custom
              zoomControlsEnabled: false, // Hide default zoom, cleaner UI
              polylines: _polylines,
              markers: _markers,
              onMapCreated: (GoogleMapController controller) {
                _controller.complete(controller);
                // Trigger first map update once map is ready
                _updateMap();
              },
            ),
          ),
        ),

        // 2. Back Button
        Positioned(
          top: 40,
          left: 20,
          child: CircleAvatar(
             backgroundColor: Colors.white,
             child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.black),
                onPressed: widget.onCancel, // Or Navigate Back
             ),
          ),
        ),

        // 3. Draggable/Floating Bottom Sheet
        DraggableScrollableSheet(
          initialChildSize: 0.38,
          minChildSize: 0.28,
          maxChildSize: 0.62,
          snap: true,
          snapSizes: const [0.28, 0.38, 0.62],
          builder: (context, scrollController) {
             return Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(30),
                    topRight: Radius.circular(30),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 20,
                      spreadRadius: 5,
                    )
                  ],
                ),
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                       // Handle Bar
                       Center(
                         child: Container(
                           width: 40,
                           height: 4,
                           decoration: BoxDecoration(
                             color: Colors.grey[300],
                             borderRadius: BorderRadius.circular(2),
                           ),
                         ),
                       ),
                       const SizedBox(height: 20),
                       
                       // Header: Ambulance Info
                        Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppPallete.primary.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.emergency, color: AppPallete.primary, size: 30),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Ambulance $ambulance",
                                  style: GoogleFonts.poppins(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87,
                                  ),
                                ),
                                _buildStatusBadge(status, eta, distanceKm),
                              ],
                            ),
                          ),
                          // Call Driver Button
                          IconButton(
                            onPressed: () {}, // TODO: Implement Call
                            icon: const CircleAvatar(
                              backgroundColor: Colors.green,
                              radius: 22,
                              child: Icon(Icons.phone, color: Colors.white, size: 20),
                            ),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 25),
                      const Divider(),
                      const SizedBox(height: 20),

                      // Status Timeline
                      _buildTimelineStep(title: 'Ambulance Dispatched', subtitle: 'Finding nearest driver', icon: Icons.emergency_share_rounded, stepIndex: 0, currentStep: currentStep),
                      _buildTimelineStep(title: 'Driver En Route', subtitle: 'Heading to your location', icon: Icons.directions_car_filled, stepIndex: 1, currentStep: currentStep),
                      _buildTimelineStep(title: 'Arrived at Scene', subtitle: 'Driver is with you', icon: Icons.location_on, stepIndex: 2, currentStep: currentStep),
                      _buildTimelineStep(title: 'To Hospital', subtitle: 'Patient being transported', icon: Icons.local_hospital, stepIndex: 3, currentStep: currentStep),
                      _buildTimelineStep(title: 'Mission Complete', subtitle: 'Arrived safely at hospital', icon: Icons.check_circle_outline_rounded, stepIndex: 4, currentStep: currentStep, isLast: true),
                      
                      const SizedBox(height: 20),

                      // Cancel button is only shown while the ambulance is still
                      // en route — once the driver marks "Arrived at Scene" (AT_PATIENT),
                      // the user is physically with the driver so cancellation makes
                      // no sense and the button is hidden.
                      if (status != 'AT_PATIENT' &&
                          status != 'TO_HOSPITAL' &&
                          status != 'COMPLETED')
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: widget.onCancel,
                            icon: const Icon(Icons.close, color: Colors.red),
                            label: const Text('Cancel Emergency', style: TextStyle(color: Colors.red)),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.red),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
             );
          }
        ),
      ],
    );
  }

  /// Formats a distance in km into a human-readable string.
  /// Below 1 km: converts to whole metres rounded to the nearest 10 m.
  /// From 1 km up: one decimal place in km.
  String _formatDistance(double km) {
    if (km < 1.0) {
      final metres = (km * 1000).round();
      // Round to nearest 10 m so "198 m" becomes "200 m"
      final rounded = ((metres + 5) ~/ 10) * 10;
      return '${rounded == 0 ? '<10' : rounded} m away';
    }
    // 1.0 km and above: 1 decimal (e.g. 1.2 km)
    return '${km.toStringAsFixed(1)} km away';
  }

  Widget _buildStatusBadge(String? status, dynamic eta, double? distanceKm) {
    switch (status) {
      case 'AT_PATIENT':
        return Row(children: [
          Container(width: 8, height: 8,
            decoration: const BoxDecoration(color: Color(0xFFD32F2F), shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text('Driver arrived at scene',
            style: GoogleFonts.inter(color: const Color(0xFFD32F2F), fontWeight: FontWeight.w700, fontSize: 13)),
        ]);
      case 'TO_HOSPITAL':
        return Row(children: [
          Container(width: 8, height: 8,
            decoration: const BoxDecoration(color: Color(0xFF1565C0), shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text('En route to hospital',
            style: GoogleFonts.inter(color: const Color(0xFF1565C0), fontWeight: FontWeight.w700, fontSize: 13)),
        ]);
      case 'COMPLETED':
        return Row(children: [
          const Icon(Icons.check_circle, size: 14, color: Colors.green),
          const SizedBox(width: 6),
          Text('Mission completed',
            style: GoogleFonts.inter(color: Colors.green, fontWeight: FontWeight.w700, fontSize: 13)),
        ]);
      default:
        // Show precise distance when available, fall back to ETA-only
        if (distanceKm != null) {
          final distStr = _formatDistance(distanceKm);
          return Row(children: [
            const Icon(Icons.navigation_rounded, size: 14, color: Colors.green),
            const SizedBox(width: 4),
            Text(
              '$distStr  ·  ETA: $eta min',
              style: GoogleFonts.inter(
                  color: Colors.green, fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ]);
        }
        return Row(children: [
          const Icon(Icons.access_time_filled, size: 14, color: Colors.green),
          const SizedBox(width: 4),
          Text('ETA: $eta mins',
            style: GoogleFonts.inter(color: Colors.green, fontWeight: FontWeight.w700, fontSize: 14)),
        ]);
    }
  }

  Widget _buildTimelineStep({
    required String title,
    required String subtitle,
    required IconData icon,
    required int stepIndex,
    required int currentStep,
    bool isLast = false,
  }) {
    final bool isCompleted = stepIndex < currentStep;
    final bool isCurrent = stepIndex == currentStep;
    final bool isPending = stepIndex > currentStep;
    const completedColor = Color(0xFF1565C0);
    const activeColor = Color(0xFFD32F2F);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 44,
          child: Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeInOut,
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isCompleted
                      ? completedColor
                      : isCurrent
                          ? activeColor
                          : Colors.grey[200],
                  boxShadow: isCurrent
                      ? [
                          BoxShadow(
                            color: activeColor.withOpacity(0.35),
                            blurRadius: 14,
                            spreadRadius: 5,
                          )
                        ]
                      : isCompleted
                          ? [
                              BoxShadow(
                                color: completedColor.withOpacity(0.2),
                                blurRadius: 6,
                                spreadRadius: 1,
                              )
                            ]
                          : null,
                ),
                child: Icon(
                  isCompleted ? Icons.check_rounded : icon,
                  color: isPending ? Colors.grey[400] : Colors.white,
                  size: 20,
                ),
              ),
              if (!isLast)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  width: 2,
                  height: 46,
                  color: stepIndex < currentStep ? completedColor : Colors.grey[200],
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 12, top: 9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: isCurrent || isCompleted ? FontWeight.w700 : FontWeight.w400,
                    color: isPending ? Colors.grey[400] : Colors.black87,
                    fontSize: 14,
                    letterSpacing: 0.15,
                  ),
                ),
                if (!isPending) ...[
                  const SizedBox(height: 3),
                  Text(
                    isCurrent ? subtitle : 'Completed',
                    style: TextStyle(
                      color: isCurrent ? activeColor : Colors.grey[500],
                      fontSize: 12,
                      fontWeight: isCurrent ? FontWeight.w500 : FontWeight.normal,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
