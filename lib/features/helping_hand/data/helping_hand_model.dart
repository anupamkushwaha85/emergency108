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
    double parseDouble(dynamic value, {double fallback = 0.0}) {
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? fallback;
      return fallback;
    }

    final latitude = parseDouble(
      json['latitude'] ?? json['lat'] ?? json['patientLat'],
    );
    final longitude = parseDouble(
      json['longitude'] ?? json['lng'] ?? json['patientLng'],
    );

    return NearbyEmergency(
      id: json['id'] ?? 0,
      type: json['type'] ?? 'Emergency',
      latitude: latitude,
      longitude: longitude,
      distanceKm: parseDouble(json['distanceKm']),
      victimName: json['victimName'] ?? 'Unknown',
      status: json['status'] ?? 'CREATED',
    );
  }
}
