class NearbyEmergency {
  final int id;
  final String type;
  final double latitude;
  final double longitude;
  final double distanceKm;
  final String victimName;
  final String status;

  NearbyEmergency({
    required this.id,
    required this.type,
    required this.latitude,
    required this.longitude,
    required this.distanceKm,
    required this.victimName,
    required this.status,
  });

  factory NearbyEmergency.fromJson(Map<String, dynamic> json) {
    return NearbyEmergency(
      id: json['id'] ?? 0,
      type: json['type'] ?? 'Emergency',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      distanceKm: (json['distanceKm'] as num?)?.toDouble() ?? 0.0,
      victimName: json['victimName'] ?? 'Unknown',
      status: json['status'] ?? 'CREATED',
    );
  }
}
