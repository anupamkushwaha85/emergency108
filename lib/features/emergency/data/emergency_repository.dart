import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/auth_session_service.dart';

final emergencyRepositoryProvider = Provider<EmergencyRepository>((ref) {
  return EmergencyRepository(ref.watch(apiClientProvider));
});

class EmergencyRepository {
  final Dio _dio;

  EmergencyRepository(this._dio);

  // 1. Create Emergency
  Future<Map<String, dynamic>> createEmergency({
    required double lat,
    required double lng,
    String? description,
    String? severity,
    String? type,
  }) async {
    try {
      final token = await _getToken();
      final response = await _dio.post(
        '/emergencies',
        data: {
          'latitude': lat,
          'longitude': lng,
          'description': description ?? 'Emergency Request',
          'severityLevel': severity ?? 'CRITICAL',
          'type': type ?? 'MEDICAL',
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      
      return response.data;
    } catch (e) {
      throw _handleError(e);
    }
  }

  // 2. Dispatch
  Future<void> dispatchEmergency(int id) async {
    try {
      final token = await _getToken();
      await _dio.post(
        '/emergencies/$id/dispatch',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } catch (e) {
      throw _handleError(e);
    }
  }

  // 3. Cancel
  Future<void> cancelEmergency(int id, {String? reason}) async {
    try {
      final token = await _getToken();
      await _dio.post(
        '/emergencies/$id/cancel',
        data: reason != null ? {'reason': reason} : null,
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } catch (e) {
      throw _handleError(e);
    }
  }



  // 5. Set Ownership (Safety Net)
  Future<void> setOwnership(int id, String emergencyFor) async {
    try {
      final token = await _getToken();
      await _dio.put(
        '/emergencies/$id/ownership',
        data: {'emergencyFor': emergencyFor},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } catch (e) {
      throw _handleError(e);
    }
  }

  // 6. Update AI Assessment
  // 6. Update AI Assessment
  Future<Map<String, dynamic>> updateAiAssessment(int id, {String? assessment, Map<String, dynamic>? triage}) async {
    try {
      final token = await _getToken();
      final data = <String, dynamic>{};
      if (assessment != null) data['assessment'] = assessment;
      if (triage != null) data['triage'] = triage;

      final response = await _dio.post(
        '/emergencies/$id/ai-assessment',
        data: data,
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return response.data;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> trackEmergency(int id) async {
    try {
      final token = await _getToken();
      final response = await _dio.get(
        '/emergencies/$id/track',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return response.data;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>?> getMyActiveEmergency() async {
    try {
      final token = await _getToken();
      final response = await _dio.get(
        '/emergencies/my-active',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      if (response.data is Map<String, dynamic>) {
        return response.data as Map<String, dynamic>;
      }
      if (response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }
      return null;
    } on DioException catch (e) {
      if (e.response?.statusCode == 204 || e.response?.statusCode == 404) {
        return null;
      }
      throw _handleError(e);
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<String> _getToken() async {
    final token = await AuthSessionService().readAuthToken();
    if (token == null) throw Exception('Auth Token not found');
    return token;
  }

  Exception _handleError(dynamic error) {
    if (error is DioException) {
      if (error.response != null) {
        final data = error.response?.data;
        if (data is Map && data['message'] != null) {
          return Exception(data['message'].toString());
        }
        if (data is String && data.isNotEmpty) {
          return Exception(data);
        }
        return Exception('API Error');
      }
      return Exception('Network Error: ${error.message}');
    }
    return Exception(error.toString());
  }
}
