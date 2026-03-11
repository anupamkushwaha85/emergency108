import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_pallete.dart';
import '../data/preferences_repository.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _isHelpingHandEnabled = true;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final repo = ref.read(preferencesRepositoryProvider);
    final enabled = await repo.isHelpingHandEnabled();
    if (mounted) {
      setState(() {
        _isHelpingHandEnabled = enabled;
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleHelpingHand(bool value) async {
    final repo = ref.read(preferencesRepositoryProvider);
    await repo.setHelpingHandEnabled(value);
    setState(() => _isHelpingHandEnabled = value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent, // Allow global background to show
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.transparent,
        foregroundColor: AppPallete.primary, // Red text for visibility
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                _buildSectionHeader('Community Response'),
                SwitchListTile(
                  title: const Text('Enable Helping Hand Alerts', style: TextStyle(color: Colors.black87)),
                  subtitle: const Text(
                    'Receive notifications for nearby emergencies where you can help.',
                    style: TextStyle(color: Colors.black54),
                  ),
                  value: _isHelpingHandEnabled,
                  onChanged: _toggleHelpingHand,
                  activeColor: AppPallete.primary,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                ),
                const Divider(color: AppPallete.lightGrey),
              ],
            ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: AppPallete.primary,
          fontWeight: FontWeight.bold,
          fontSize: 12,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
