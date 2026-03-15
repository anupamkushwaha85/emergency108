import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/network/api_client.dart';

final driverRepositoryProvider = Provider<DriverRepository>((ref) {
  return DriverRepository(ref.watch(apiClientProvider));
});

class DriverRepository {
  final Dio _dio;

  DriverRepository(this._dio);

  // 0. Upload Verification Document
  Future<void> uploadDocument(String base64Data) async {
    try {
      final token = await _getToken();
      await _dio.post(
        '/driver/upload-document',
        data: {'documentData': base64Data},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } catch (e) {
      throw _handleError(e);
    }
  }

  // 1. Start Shift
  Future<Map<String, dynamic>> startShift(int ambulanceId) async {
    try {
      final token = await _getToken();
      final response = await _dio.post(
        '/driver/start-shift',
        data: {'ambulanceId': ambulanceId},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return response.data;
    } catch (e) {
      throw _handleError(e);
    }
  }

  // 1b. Get the ambulance assigned to this driver (auto-detect before start-shift)
  Future<int?> getMyAmbulanceId() async {
    try {
      final token = await _getToken();
      final response = await _dio.get(
        '/driver/my-ambulance',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final dynamic ambulanceId = response.data['ambulanceId'];
      if (ambulanceId == null) return null;
      return int.tryParse(ambulanceId.toString());
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        // Endpoint exists but driver has no ambulance assigned
        return null;
      }
      // Network or unexpected server error — surface it
      throw _handleError(e);
    } catch (e) {
      throw Exception('Failed to fetch ambulance: $e');
    }
  }

  // 2. End Shift
  Future<void> endShift() async {
    try {
      final token = await _getToken();
      await _dio.post(
        '/driver/end-shift',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } catch (e) {
      throw _handleError(e);
    }
  }

  // 3. Get Assigned Emergency
  Future<Map<String, dynamic>?> getAssignedEmergency() async {
    try {
      final token = await _getToken();
      final response = await _dio.get(
        '/driver/emergencies/assigned',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      
      if (response.data['assigned'] == true) {
        return response.data;
      }
      return null;
    } catch (e) {
      // If 404 or other errors, might mean no assignment
      return null;
    }
  }

  // 4. Accept Emergency
  Future<void> acceptEmergency(int emergencyId) async {
    try {
      final token = await _getToken();
      await _dio.post(
        '/driver/emergencies/$emergencyId/accept',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } catch (e) {
      throw _handleError(e);
    }
  }

  // 5. Reject Emergency
  Future<void> rejectEmergency(int emergencyId) async {
    try {
      final token = await _getToken();
      await _dio.post(
        '/driver/emergencies/$emergencyId/reject',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } catch (e) {
      throw _handleError(e);
    }
  }

  // 8. Mark Arrived at Patient
  Future<void> markArrivedAtPatient(int emergencyId) async {
    try {
      final token = await _getToken();
      await _dio.post(
        '/emergencies/$emergencyId/arrive',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } catch (e) {
      throw _handleError(e);
    }
  }

  // 9. Mark Patient Picked Up (assigns nearest hospital)
  Future<Map<String, dynamic>> markPatientPickedUp(int emergencyId, double patientLat, double patientLng) async {
    try {
      final token = await _getToken();
      final response = await _dio.post(
        '/driver/mark-patient-picked-up',
        data: {
          'emergencyId': emergencyId,
          'patientLat': patientLat,
          'patientLng': patientLng,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return response.data; // Returns hospital info
    } catch (e) {
      throw _handleError(e);
    }
  }

  // 10. Complete Mission (validates 100m proximity to hospital)
  Future<Map<String, dynamic>> completeMission(int emergencyId, double currentLat, double currentLng) async {
    try {
      final token = await _getToken();
      final response = await _dio.post(
        '/driver/complete-mission',
        data: {
          'emergencyId': emergencyId,
          'currentLat': currentLat,
          'currentLng': currentLng,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return response.data;
    } catch (e) {
      // Will throw if too far from hospital (403 Forbidden)
      throw _handleError(e);
    }
  }

  // 10b. Cancel Mission (driver-initiated — releases driver + ambulance, notifies patient)
  Future<void> cancelMission(int emergencyId) async {
    try {
      final token = await _getToken();
      await _dio.post(
        '/driver/cancel-mission',
        data: {'emergencyId': emergencyId},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } catch (e) {
      throw _handleError(e);
    }
  }

  // 6. Get Verification Status
  Future<String> getVerificationStatus() async {
    try {
      final token = await _getToken();
      final response = await _dio.get(
        '/driver/verification-status',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return response.data['verificationStatus'].toString();
    } catch (e) {
      // return 'UNVERIFIED'; // Default if error or not found
      throw _handleError(e);
    }
  }

  // 11. Update Location (Heartbeat)
  Future<void> updateLocation(double lat, double lng) async {
    try {
      final token = await _getToken();
      await _dio.put(
        '/driver/location',
        data: {'lat': lat, 'lng': lng},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } catch (e) {
       // Silent fail for heartbeat, or throw if critical
       // throw _handleError(e);
    }
  }

  // 7. Get Driver Online Status (legacy — simple bool)
  Future<bool> getDriverStatus() async {
    try {
      final token = await _getToken();
      final response = await _dio.get(
        '/driver/status',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return response.data['isOnline'] == true;
    } catch (e) {
      return false;
    }
  }

  // 7b. Get full session state (isOnline + sessionStatus + hasOngoingMission)
  // Use this on app startup to properly restore driver state after restart.
  Future<Map<String, dynamic>> getSessionState() async {
    try {
      final token = await _getToken();
      final response = await _dio.get(
        '/driver/status',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return {
        'isOnline': response.data['isOnline'] == true,
        'sessionStatus': response.data['sessionStatus']?.toString() ?? 'NONE',
        'hasOngoingMission': response.data['hasOngoingMission'] == true,
      };
    } catch (e) {
      return {'isOnline': false, 'sessionStatus': 'NONE', 'hasOngoingMission': false};
    }
  }

  Future<String> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
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
