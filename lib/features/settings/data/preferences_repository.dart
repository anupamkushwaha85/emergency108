import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/network/api_client.dart';

final preferencesRepositoryProvider = Provider((ref) => PreferencesRepository(ref));

class PreferencesRepository {
  final Ref ref;
  static const String _keyHelpingHand = 'isHelpingHandEnabled';

  PreferencesRepository(this.ref);

  Future<bool> isHelpingHandEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyHelpingHand) ?? true; // Default to TRUE
  }

  Future<void> setHelpingHandEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyHelpingHand, value);

    // Sync with server
    try {
      final dio = ref.read(apiClientProvider);
      await dio.put('/users/preferences/helping-hand', data: {'enabled': value});
    } catch (e, st) {
      ref.read(apiClientProvider).interceptors.add(LogInterceptor(logPrint: (o) => debugPrint(o.toString()))); // Ensure logs are on
      debugPrint("Stack: $st");
      // Silent fail if offline, but locally saved
    }
  }
}
