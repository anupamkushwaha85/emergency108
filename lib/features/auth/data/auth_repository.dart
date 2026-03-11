import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/api_client.dart';
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(apiClientProvider));
});

class AuthRepository {
  final Dio _dio;

  AuthRepository(this._dio);

  Future<void> sendOtp(String phoneNumber, String role) async {
    try {
      await _dio.post('/auth/send-otp', data: {
        'phone': phoneNumber,
        'role': role,
      });
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<String> verifyOtp(String phoneNumber, String otp) async {
    try {
      final response = await _dio.post('/auth/verify-otp', data: {
        'phone': phoneNumber,
        'otp': otp,
      });
      final data = response.data;
      final token = data['token'];
      // Backend response is flat: {"token": "...", "role": "DRIVER", "name": "...", "profileComplete": true}
      
      // Save token and user details locally
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_token', token);
      
      // Parse flat fields
      await prefs.setString('user_name', data['name'] ?? '');
      if (data['userId'] != null) {
        await prefs.setInt('user_id', data['userId']);
      }
      await prefs.setString('user_phone', data['phone'] ?? '');
      await prefs.setString('user_role', data['role'] ?? 'PUBLIC');
      await prefs.setString('user_address', data['address'] ?? ''); // Might be null/missing in this response
      await prefs.setString('user_email', data['email'] ?? '');     // Might be null/missing in this response
       
      // Check profile completion based on API flag if available, or fallback to check
      bool isProfileComplete = data['profileComplete'] ?? false;
      if (data['profileComplete'] == null) {
          // Fallback logic if backend doesn't send flag (though logs show it does)
          isProfileComplete = (data['name'] != null && !data['name'].toString().startsWith('User ')) &&
                              (data['address'] != null && data['address'].toString().isNotEmpty);
      }
          
      await prefs.setBool('is_profile_complete', isProfileComplete);
      
      return token;
    } catch (e) {
      throw _handleError(e);
    }
  }
  
  Exception _handleError(dynamic error) {
    if (error is DioException) {
      if (error.response != null) {
        return Exception(error.response?.data['message'] ?? 'API Error');
      }
      return Exception('Network Error: ${error.message}');
    }
    return Exception(error.toString());
  }

  /// Register FCM token for push notifications
  Future<void> registerFcmToken(String fcmToken) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      if (token == null) {
        print('⚠️ Cannot register FCM token: no auth token in storage');
        return;
      }
      await _dio.post(
        '/users/register-fcm-token',
        data: {'fcmToken': fcmToken},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      print('✅ FCM token registered successfully');
    } catch (e) {
      print('❌ Failed to register FCM token: $e');
      // Don't throw - this shouldn't block login
    }
  }
}
