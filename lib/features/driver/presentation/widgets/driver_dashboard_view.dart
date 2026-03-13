import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../../core/theme/app_theme.dart';

class DriverDashboardView extends StatefulWidget {
  final bool isOnline;
  final bool isLoading;
  final VoidCallback onToggleOnline;
  final Position? currentPosition;

  const DriverDashboardView({
    super.key,
    required this.isOnline,
    required this.isLoading,
    required this.onToggleOnline,
    this.currentPosition,
  });

  @override
  State<DriverDashboardView> createState() => _DriverDashboardViewState();
}

class _DriverDashboardViewState extends State<DriverDashboardView> {
  final Completer<GoogleMapController> _mapController = Completer();
  bool _hasFocusedDriverOnce = false;

  Future<void> _focusOnDriver(Position position, {bool forceZoom = false}) async {
    if (!_mapController.isCompleted) return;
    final controller = await _mapController.future;
    await controller.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(position.latitude, position.longitude),
          zoom: forceZoom ? 17.0 : 16.2,
          tilt: 35,
          bearing: 0,
        ),
      ),
    );
  }

  @override
  void didUpdateWidget(DriverDashboardView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Quickly focus with zoom when first GPS fix arrives, then keep smooth updates.
    if (widget.currentPosition != null &&
        widget.currentPosition != oldWidget.currentPosition &&
        _mapController.isCompleted) {
      _focusOnDriver(
        widget.currentPosition!,
        forceZoom: oldWidget.currentPosition == null || !_hasFocusedDriverOnce,
      );
      _hasFocusedDriverOnce = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isOnline) {
      return _buildOnlineView();
    }
    return _buildOfflineView();
  }

  // ── ONLINE: full-screen map + floating button ───────────────────────────────
  Widget _buildOnlineView() {
    final pos = widget.currentPosition;
    final initialCam = pos != null
      ? CameraPosition(target: LatLng(pos.latitude, pos.longitude), zoom: 16.2)
        : const CameraPosition(target: LatLng(20.5937, 78.9629), zoom: 5); // India

    final driverMarkers = pos != null
        ? {
            Marker(
              markerId: const MarkerId('driver'),
              position: LatLng(pos.latitude, pos.longitude),
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
              infoWindow: const InfoWindow(title: 'You are here'),
            )
          }
        : <Marker>{};

    return Stack(
      children: [
        // ── Background map ──
        GoogleMap(
          initialCameraPosition: initialCam,
          myLocationEnabled: false, // we use custom marker
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          compassEnabled: false,
          mapToolbarEnabled: false,
          style: _darkMapStyle,
          markers: driverMarkers,
          onMapCreated: (c) {
            if (!_mapController.isCompleted) _mapController.complete(c);
            if (pos != null) {
              // Ensure driver gets a close map focus immediately on entering online mode.
              Future.delayed(const Duration(milliseconds: 250), () {
                if (mounted) {
                  _focusOnDriver(pos, forceZoom: true);
                  _hasFocusedDriverOnce = true;
                }
              });
            }
          },
        ),

        // ── Subtle top gradient so app bar remains readable ──
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 120,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black.withOpacity(0.6), Colors.transparent],
              ),
            ),
          ),
        ),

        // ── Bottom panel: status + button ──
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: _buildOnlineBottomPanel(),
        ),
      ],
    );
  }

  Widget _buildOnlineBottomPanel() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 36),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withOpacity(0.92),
            Colors.black.withOpacity(0.75),
            Colors.transparent,
          ],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Status chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.green.withOpacity(0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.greenAccent,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'ONLINE · Awaiting Requests',
                  style: GoogleFonts.inter(
                    color: Colors.greenAccent,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Circular GO OFFLINE button
          GestureDetector(
            onTap: widget.isLoading ? null : widget.onToggleOnline,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Colors.green, Color(0xFF006400)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.green.withOpacity(0.45),
                    blurRadius: 28,
                    spreadRadius: 4,
                    offset: const Offset(0, 8),
                  ),
                ],
                border: Border.all(color: Colors.white.withOpacity(0.15), width: 3),
              ),
              child: Center(
                child: widget.isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.power_settings_new, size: 46, color: Colors.white.withOpacity(0.9)),
                          const SizedBox(height: 6),
                          Text(
                            'STOP',
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2.0,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Tap to go offline',
            style: GoogleFonts.inter(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }

  // ── OFFLINE: simple centered layout ────────────────────────────────────────
  Widget _buildOfflineView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Verified badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.green.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.verified, color: Colors.green[700], size: 18),
                const SizedBox(width: 8),
                Text(
                  'VERIFIED PARTNER',
                  style: GoogleFonts.inter(
                    color: Colors.green[700],
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),

          Text(
            'You are Offline',
            style: GoogleFonts.poppins(
              color: AppTheme.black,
              fontSize: 32,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 10),

          Text(
            'Go online to receive requests',
            style: GoogleFonts.inter(color: Colors.black54, fontSize: 16),
          ),
          const SizedBox(height: 60),

          // Circular GO ONLINE button
          GestureDetector(
            onTap: widget.isLoading ? null : widget.onToggleOnline,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [AppTheme.primaryRed, const Color(0xFF990000)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryRed.withOpacity(0.4),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  ),
                ],
                border: Border.all(color: Colors.black12, width: 4),
              ),
              child: Center(
                child: widget.isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.power_settings_new, size: 60, color: Colors.white.withOpacity(0.9)),
                          const SizedBox(height: 8),
                          Text(
                            'GO',
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 32,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2.0,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Subtle dark map style for an emergency / professional feel
const String _darkMapStyle = '''
[
  {"elementType":"geometry","stylers":[{"color":"#1d2c4d"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#8ec3b9"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#1a3646"}]},
  {"featureType":"administrative.country","elementType":"geometry.stroke","stylers":[{"color":"#4b6878"}]},
  {"featureType":"administrative.land_parcel","elementType":"labels.text.fill","stylers":[{"color":"#64779e"}]},
  {"featureType":"administrative.province","elementType":"geometry.stroke","stylers":[{"color":"#4b6878"}]},
  {"featureType":"landscape.man_made","elementType":"geometry.stroke","stylers":[{"color":"#334e87"}]},
  {"featureType":"landscape.natural","elementType":"geometry","stylers":[{"color":"#023e58"}]},
  {"featureType":"poi","elementType":"geometry","stylers":[{"color":"#283d6a"}]},
  {"featureType":"poi","elementType":"labels.text.fill","stylers":[{"color":"#6f9ba5"}]},
  {"featureType":"poi","elementType":"labels.text.stroke","stylers":[{"color":"#1d2c4d"}]},
  {"featureType":"poi.park","elementType":"geometry.fill","stylers":[{"color":"#023e58"}]},
  {"featureType":"poi.park","elementType":"labels.text.fill","stylers":[{"color":"#3C7680"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#304a7d"}]},
  {"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#98a5be"}]},
  {"featureType":"road","elementType":"labels.text.stroke","stylers":[{"color":"#1d2c4d"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#2c6675"}]},
  {"featureType":"road.highway","elementType":"geometry.stroke","stylers":[{"color":"#255763"}]},
  {"featureType":"road.highway","elementType":"labels.text.fill","stylers":[{"color":"#b0d5ce"}]},
  {"featureType":"road.highway","elementType":"labels.text.stroke","stylers":[{"color":"#023747"}]},
  {"featureType":"transit","elementType":"labels.text.fill","stylers":[{"color":"#98a5be"}]},
  {"featureType":"transit","elementType":"labels.text.stroke","stylers":[{"color":"#1d2c4d"}]},
  {"featureType":"transit.line","elementType":"geometry.fill","stylers":[{"color":"#283d6a"}]},
  {"featureType":"transit.station","elementType":"geometry","stylers":[{"color":"#3a4762"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#0e1626"}]},
  {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#4e6d70"}]}
]
''';
