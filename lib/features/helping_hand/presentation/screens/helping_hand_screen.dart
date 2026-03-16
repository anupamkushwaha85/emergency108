import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/theme/app_pallete.dart';
import '../../data/helping_hand_model.dart';
import '../../data/helping_hand_repository.dart';
import '../../../settings/data/preferences_repository.dart';

// ─── Main Screen ──────────────────────────────────────────────────────────────

class HelpingHandScreen extends ConsumerStatefulWidget {
  const HelpingHandScreen({super.key});

  @override
  ConsumerState<HelpingHandScreen> createState() => _HelpingHandScreenState();
}

class _HelpingHandScreenState extends ConsumerState<HelpingHandScreen> {
  List<NearbyEmergency> _emergencies = [];
  bool _isLoading = true;
  bool _isEnabled = true;
  Position? _currentPosition;

  @override
  void initState() {
    super.initState();
    _checkStatusAndLoad();
  }

  @override
  void dispose() {
    super.dispose();
  }

  // ─── Data loading ─────────────────────────────────────────────────────────────

  Future<void> _checkStatusAndLoad() async {
    final prefsRepo = ref.read(preferencesRepositoryProvider);
    final enabled = await prefsRepo.isHelpingHandEnabled();

    if (!enabled) {
      if (mounted) {
        setState(() {
          _isEnabled = false;
          _isLoading = false;
          _emergencies = [];
        });
      }
      return;
    }

    if (mounted && !_isEnabled) setState(() => _isEnabled = true);
    _loadData();
  }

  Future<void> _loadData() async {
    if (_emergencies.isEmpty && mounted) setState(() => _isLoading = true);

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) setState(() => _isLoading = false);
          return;
        }
      }

      _currentPosition = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 5),
        ),
      );

      if (_currentPosition != null) {
        final repo = ref.read(helpingHandRepositoryProvider);
        await repo.updateLocation(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
        );
        final list = await repo.getNearbyEmergencies();
        if (mounted) setState(() { _emergencies = list; _isLoading = false; });
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('❌ Error loading helping hand data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─── Open in-app map bottom sheet ────────────────────────────────────────────

  void _openMapSheet(NearbyEmergency item) {
    final hasValidCoordinates =
        item.latitude.abs() > 0.0001 || item.longitude.abs() > 0.0001;
    if (!hasValidCoordinates) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location is not available for this emergency yet. Please refresh and try again.'),
          backgroundColor: AppPallete.error,
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EmergencyMapSheet(
        emergency: item,
        userPosition: _currentPosition,
      ),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_isEnabled) return _disabledView();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F4F8),
      appBar: _buildAppBar(),
      body: RefreshIndicator(
        color: AppPallete.primary,
        onRefresh: _checkStatusAndLoad,
        child: _isLoading && _emergencies.isEmpty
            ? const Center(
                child: CircularProgressIndicator(color: AppPallete.primary),
              )
            : CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(child: _buildHeader()),
                  if (_emergencies.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _buildEmptyState(),
                    )
                  else ...[
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      sliver: SliverToBoxAdapter(
                        child: Text(
                          '${_emergencies.length} emergency nearby',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFFF2B2B),
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (ctx, i) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _buildEmergencyCard(_emergencies[i]),
                          ),
                          childCount: _emergencies.length,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  // ─── Widgets ──────────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 1,
      shadowColor: const Color(0x1A000000),
      surfaceTintColor: Colors.white,
      automaticallyImplyLeading: false,
      titleSpacing: 16,
      title: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: Color(0xFFFFEBEB),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.volunteer_activism_rounded,
              color: Color(0xFFFF2B2B),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Helping Hand',
                style: TextStyle(
                  color: Color(0xFF1A1A1A),
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'Nearby emergencies · pull to refresh',
                style: TextStyle(color: Color(0xFF888888), fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Color(0x0D000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: Color(0xFFFFEBEB),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.shield_rounded,
              color: Color(0xFFFF2B2B),
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'You are a Community Responder',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Even small help matters. Stay safe — always wait\nfor professional teams before intervening.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF777777), height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Empty state ──────────────────────────────────────────────────────────────

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Illustration
          Container(
            width: 120,
            height: 120,
            decoration: const BoxDecoration(
              color: Color(0xFFFFEBEB),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.favorite_rounded,
              size: 58,
              color: Color(0xFFFF2B2B),
            ),
          ),
          const SizedBox(height: 28),

          // Headline
          const Text(
            'All clear around you',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A1A1A),
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 10),

          // Subtext
          const Text(
            "There are no emergencies near you right now.\nWe'll notify you the moment someone nearby needs help.",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFF777777),
              height: 1.6,
            ),
          ),
          const SizedBox(height: 32),

          // Divider with quote
          const Row(
            children: [
              Expanded(child: Divider(color: Color(0xFFE0E0E0))),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Icon(Icons.format_quote_rounded, color: Color(0xFFDDDDDD), size: 22),
              ),
              Expanded(child: Divider(color: Color(0xFFE0E0E0))),
            ],
          ),
          const SizedBox(height: 20),

          // Quote
          const Text(
            '"The smallest act of kindness is worth more than the grandest intention."',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontStyle: FontStyle.italic,
              color: Color(0xFF555555),
              height: 1.6,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '— Oscar Wilde',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFFAAAAAA),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 36),

          // Pull-to-refresh hint
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: const Color(0xFFE8E8E8)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.refresh_rounded, size: 16, color: Color(0xFF888888)),
                SizedBox(width: 8),
                Text(
                  'Pull down to check again',
                  style: TextStyle(fontSize: 13, color: Color(0xFF888888)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Emergency card ───────────────────────────────────────────────────────────

  Widget _buildEmergencyCard(NearbyEmergency item) {
    return GestureDetector(
      onTap: () => _openMapSheet(item),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFFDDDD), width: 1.5),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0FFF2B2B),
              blurRadius: 10,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          children: [
            // Top row
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Row(
                children: [
                  // Emergency icon
                  Container(
                    width: 52,
                    height: 52,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFFEBEB),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.emergency_rounded,
                      color: Color(0xFFFF2B2B),
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${item.type} Emergency',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1A1A1A),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(
                              Icons.location_on_rounded,
                              size: 14,
                              color: Color(0xFFFF2B2B),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '${item.distanceKm.toStringAsFixed(1)} km away',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFFF2B2B),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Chevron hint
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xFFCCCCCC),
                    size: 24,
                  ),
                ],
              ),
            ),

            const Divider(height: 1, color: Color(0xFFF0F0F0)),

            // Bottom row
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Row(
                children: [
                  // Victim
                  const Icon(Icons.person_outline_rounded, size: 16, color: Color(0xFF888888)),
                  const SizedBox(width: 5),
                  Text(
                    item.victimName,
                    style: const TextStyle(fontSize: 13, color: Color(0xFF555555)),
                  ),

                  // Status badge
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3CD),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      item.status,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF856404),
                      ),
                    ),
                  ),

                  const Spacer(),

                  // Tap-to-view map button
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF2B2B),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.map_rounded, size: 15, color: Colors.white),
                        SizedBox(width: 6),
                        Text(
                          'View on map',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Disabled feature view ────────────────────────────────────────────────────

  Scaffold _disabledView() {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F4F8),
      appBar: AppBar(
        title: const Text('Helping Hand'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A1A),
        elevation: 1,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 90,
                height: 90,
                decoration: const BoxDecoration(
                  color: Color(0xFFF0F0F0),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.volunteer_activism_outlined,
                  size: 44,
                  color: Color(0xFFBBBBBB),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Feature Disabled',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFF333333)),
              ),
              const SizedBox(height: 10),
              const Text(
                'Enable Helping Hand in Settings to start\nseeing nearby emergencies.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF888888), height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── In-app map bottom sheet ──────────────────────────────────────────────────

class _EmergencyMapSheet extends StatefulWidget {
  final NearbyEmergency emergency;
  final Position? userPosition;

  const _EmergencyMapSheet({required this.emergency, this.userPosition});

  @override
  State<_EmergencyMapSheet> createState() => _EmergencyMapSheetState();
}

class _EmergencyMapSheetState extends State<_EmergencyMapSheet> {
  GoogleMapController? _mapController;

  late final LatLng _target = LatLng(
    widget.emergency.latitude,
    widget.emergency.longitude,
  );

  LatLng? get _userLatLng => widget.userPosition != null
      ? LatLng(widget.userPosition!.latitude, widget.userPosition!.longitude)
      : null;

  late final Set<Marker> _markers = {
    Marker(
      markerId: const MarkerId('emergency'),
      position: _target,
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      infoWindow: InfoWindow(
        title: '${widget.emergency.type} Emergency',
        snippet: '${widget.emergency.distanceKm.toStringAsFixed(1)} km away · ${widget.emergency.victimName}',
      ),
    ),
    if (_userLatLng != null)
      Marker(
        markerId: const MarkerId('my_location'),
        position: _userLatLng!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        infoWindow: const InfoWindow(title: 'You'),
      ),
  };

  void _fitBounds() {
    if (_mapController == null || _userLatLng == null) return;
    final bounds = LatLngBounds(
      southwest: LatLng(
        _target.latitude < _userLatLng!.latitude ? _target.latitude : _userLatLng!.latitude,
        _target.longitude < _userLatLng!.longitude ? _target.longitude : _userLatLng!.longitude,
      ),
      northeast: LatLng(
        _target.latitude > _userLatLng!.latitude ? _target.latitude : _userLatLng!.latitude,
        _target.longitude > _userLatLng!.longitude ? _target.longitude : _userLatLng!.longitude,
      ),
    );
    _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
  }

  Future<void> _openGoogleMapsNavigation() async {
    final url = Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
      '&destination=${widget.emergency.latitude},${widget.emergency.longitude}'
      '&travelmode=walking',
    );
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFDDDDDD),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFFEBEB),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.emergency_rounded,
                        color: Color(0xFFFF2B2B),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${widget.emergency.type} Emergency',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1A1A1A),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              const Icon(Icons.location_on_rounded, size: 13, color: Color(0xFFFF2B2B)),
                              const SizedBox(width: 3),
                              Text(
                                '${widget.emergency.distanceKm.toStringAsFixed(1)} km away',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFFFF2B2B),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 10),
                              const Icon(Icons.person_outline_rounded, size: 13, color: Color(0xFF888888)),
                              const SizedBox(width: 3),
                              Text(
                                widget.emergency.victimName,
                                style: const TextStyle(fontSize: 13, color: Color(0xFF555555)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Close
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Icon(Icons.close_rounded, color: Color(0xFF888888)),
                    ),
                  ],
                ),
              ),

              const Divider(height: 1, color: Color(0xFFF0F0F0)),

              // Map
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
                  child: GoogleMap(
                    initialCameraPosition: CameraPosition(target: _target, zoom: 15.5),
                    markers: _markers,
                    myLocationEnabled: true,
                    myLocationButtonEnabled: true,
                    zoomControlsEnabled: false,
                    onMapCreated: (ctrl) {
                      _mapController = ctrl;
                      // Show info window and fit bounds after a short delay
                      Future.delayed(
                        const Duration(milliseconds: 600),
                        () {
                          ctrl.showMarkerInfoWindow(const MarkerId('emergency'));
                          _fitBounds();
                        },
                      );
                    },
                  ),
                ),
              ),

              // Navigate button
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _openGoogleMapsNavigation,
                    icon: const Icon(Icons.directions_walk_rounded, size: 20),
                    label: const Text(
                      'Navigate to Emergency',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF2B2B),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 4,
                      shadowColor: const Color(0x40FF2B2B),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

