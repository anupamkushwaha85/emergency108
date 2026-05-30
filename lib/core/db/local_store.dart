import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class LocalStore {
  static const _activeEmergencyKey = 'active_emergency';
  static const _queuedLocationsKey = 'queued_locations';
  static const _lastEventSeqKeyPrefix = 'last_event_seq_';

  Future<void> saveActiveEmergency(Map<String, dynamic> json) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeEmergencyKey, jsonEncode(json));
  }

  Future<Map<String, dynamic>?> getActiveEmergency() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_activeEmergencyKey);
    if (s == null) return null;
    try {
      return jsonDecode(s) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> clearActiveEmergency() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_activeEmergencyKey);
  }

  Future<void> enqueueLocation(Map<String, dynamic> loc) async {
    final prefs = await SharedPreferences.getInstance();
    final listS = prefs.getString(_queuedLocationsKey);
    List<dynamic> list = [];
    if (listS != null) {
      try {
        list = jsonDecode(listS) as List<dynamic>;
      } catch (_) {
        list = [];
      }
    }
    list.add(loc);
    await prefs.setString(_queuedLocationsKey, jsonEncode(list));
  }

  Future<List<Map<String, dynamic>>> getQueuedLocations() async {
    final prefs = await SharedPreferences.getInstance();
    final listS = prefs.getString(_queuedLocationsKey);
    if (listS == null) return [];
    try {
      final list = jsonDecode(listS) as List<dynamic>;
      return list.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  Future<void> removeQueuedLocations(List<String> clientRequestIds) async {
    final prefs = await SharedPreferences.getInstance();
    final listS = prefs.getString(_queuedLocationsKey);
    if (listS == null) return;
    try {
      final list = (jsonDecode(listS) as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .where((e) => !clientRequestIds.contains(e['clientRequestId']))
          .toList();
      await prefs.setString(_queuedLocationsKey, jsonEncode(list));
    } catch (_) {
      await prefs.remove(_queuedLocationsKey);
    }
  }

  Future<void> setLastEventSeq(String emergencyId, int seq) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('$_lastEventSeqKeyPrefix$emergencyId', seq);
  }

  Future<int?> getLastEventSeq(String emergencyId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('$_lastEventSeqKeyPrefix$emergencyId');
  }
}
