import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'dart:developer' as developer;

import '../../../../core/network/api_client.dart';
import '../../../../core/services/auth_session_service.dart';
import '../../../../core/db/local_store.dart';
import 'helping_hand_model.dart';

final helpingHandRepositoryProvider = Provider<HelpingHandRepository>((ref) {
  return HelpingHandRepository(ref.watch(apiClientProvider));
});

class HelpingHandRepository {
  final Dio _dio;
  final _local = LocalStore();
  final _uuid = const Uuid();

  HelpingHandRepository(this._dio);

  Future<void> updateLocation(double lat, double lng) async {
    final clientRequestId = _uuid.v4();
    final payload = {
      'clientRequestId': clientRequestId,
      'lat': lat,
      'lng': lng,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    };

    // Persist locally first so we never lose this update if the app is killed
    try {
      await _local.enqueueLocation(payload);
    } catch (e) {
      developer.log('Failed to enqueue location locally: $e');
    }

    // Attempt to deliver immediately; if it fails, it remains queued
    try {
      final token = await _getToken();
      final userId = await _getUserId();
      final response = await _dio.post(
        '/helping-hand/location',
        queryParameters: {'userId': userId},
        data: payload,
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      // On success, remove from queue
      if (response.statusCode != null && response.statusCode! >= 200 && response.statusCode! < 300) {
        await _local.removeQueuedLocations([clientRequestId]);
      }
    } catch (e) {
      developer.log('Network delivery failed; will retry later: $e');
    }
  }

  /// Try to flush any queued location updates. Returns number of successfully delivered items.
  Future<int> flushQueuedLocations() async {
    final queued = await _local.getQueuedLocations();
    if (queued.isEmpty) return 0;
    final deliveredIds = <String>[];
    try {
      final token = await _getToken();
      final userId = await _getUserId();
      for (final item in queued) {
        final clientId = item['clientRequestId'] as String?;
        try {
          final resp = await _dio.post(
            '/helping-hand/location',
            queryParameters: {'userId': userId},
            data: item,
            options: Options(headers: {'Authorization': 'Bearer $token'}),
          );
          if (resp.statusCode != null && resp.statusCode! >= 200 && resp.statusCode! < 300) {
            if (clientId != null) deliveredIds.add(clientId);
          }
        } catch (e) {
          // stop on first failure to preserve ordering and retry later
          developer.log('Flush failed for item $clientId: $e');
          break;
        }
      }
      if (deliveredIds.isNotEmpty) {
        await _local.removeQueuedLocations(deliveredIds);
      }
    } catch (e) {
      developer.log('Flush queued locations failed: $e');
    }
    return deliveredIds.length;
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
