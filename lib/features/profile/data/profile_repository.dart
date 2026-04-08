import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/auth_session_service.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(ref.watch(apiClientProvider));
});

class ProfileRepository {
  final Dio _dio;

  ProfileRepository(this._dio);

  Future<void> updateProfile({
    required String name,
    required String address,
    required String gender,
    required String dateOfBirth, // Format: yyyy-MM-dd
    required int age,
    String? email,
    String? bloodGroup,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = await AuthSessionService().readAuthToken();
      
      if (token == null) throw Exception('No auth token found');

      final response = await _dio.put(
        '/auth/profile',
        data: {
          'name': name,
          'address': address,
          'gender': gender,
          'dateOfBirth': dateOfBirth,
          'age': age,
          if (email != null && email.isNotEmpty) 'email': email,
          if (bloodGroup != null && bloodGroup.isNotEmpty && bloodGroup != 'Select') 
            'bloodGroup': bloodGroup,
        },
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
        ),
      );
      
      // Update local profile status
      if (response.statusCode == 200) {
        await prefs.setBool('is_profile_complete', true);
        await prefs.setString('user_name', name);
        await prefs.setString('user_address', address);
        await prefs.setString('user_gender', gender);
        await prefs.setString('user_dob', dateOfBirth);
        await prefs.setInt('user_age', age);
        if (email != null) await prefs.setString('user_email', email);
        if (bloodGroup != null) await prefs.setString('user_blood_group', bloodGroup);
      }
      
    } catch (e) {
      throw _handleError(e);
    }
  }
  
  // Helper to get cached user profile
  Future<Map<String, String>> getUserProfile() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'name': prefs.getString('user_name') ?? '',
      'address': prefs.getString('user_address') ?? '',
      'email': prefs.getString('user_email') ?? '',
      'gender': prefs.getString('user_gender') ?? 'Male',
      'dob': prefs.getString('user_dob') ?? '',
      'bloodGroup': prefs.getString('user_blood_group') ?? 'Select',
    };
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
}
