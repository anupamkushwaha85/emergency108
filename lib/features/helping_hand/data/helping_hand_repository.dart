import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/auth_session_service.dart';
import 'helping_hand_model.dart';

final helpingHandRepositoryProvider = Provider<HelpingHandRepository>((ref) {
  return HelpingHandRepository(ref.watch(apiClientProvider));
});

class HelpingHandRepository {
  final Dio _dio;

  HelpingHandRepository(this._dio);

  Future<void> updateLocation(double lat, double lng) async {
    try {
      final token = await _getToken();
      final userId = await _getUserId();
      await _dio.post(
        '/helping-hand/location',
        queryParameters: {'userId': userId},
        data: {
          'lat': lat,
          'lng': lng,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } catch (e) {
      // Fail silently for background updates
    }
  }

  Future<List<NearbyEmergency>> getNearbyEmergencies() async {
    try {
      final token = await _getToken();
      final userId = await _getUserId();
      final response = await _dio.get(
        '/helping-hand/nearby',
        queryParameters: {
          'userId': userId,
          'radiusKm': 3.0,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      final List<dynamic> list = response.data;
      return list.map((e) => NearbyEmergency.fromJson(e)).toList();
    } catch (e) {
      // PRINT ERROR to console so we can debug
      print("❌ Error fetching nearby emergencies: $e");
      return []; // Return empty on error to avoid crashing polling
    }
  }

  Future<String> _getToken() async {
    final token = await AuthSessionService().readAuthToken();
    if (token == null) throw Exception('Auth Token not found');
    return token;
  }
  
  Future<int> _getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getInt('user_id');
    if (id == null) throw Exception('User ID not found');
    return id;
  }
}
