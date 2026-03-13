import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_pallete.dart';
import '../../data/emergency_repository.dart';

class OwnershipModal extends ConsumerStatefulWidget {
  /// Notifier that carries the real emergency id once the API call resolves.
  /// The modal shows a loading spinner until the id is non-zero, then allows
  /// the user to make a decision. This lets the modal appear instantly while
  /// GPS + API work in the background.
  final ValueNotifier<int?> emergencyIdNotifier;
  final ValueChanged<String> onDecisionMade;
  final VoidCallback? onCancel;

  const OwnershipModal({
    super.key,
    required this.emergencyIdNotifier,
    required this.onDecisionMade,
    this.onCancel,
  });

  @override
  ConsumerState<OwnershipModal> createState() => _OwnershipModalState();
}

class _OwnershipModalState extends ConsumerState<OwnershipModal> {
  bool _isLoading = false;

  Future<void> _makeDecision(String ownership) async {
    final id = widget.emergencyIdNotifier.value;
    if (id == null) return; // shouldn't happen — buttons are hidden until id arrives

    setState(() => _isLoading = true);
    try {
      await ref.read(emergencyRepositoryProvider).setOwnership(id, ownership);
      if (mounted) {
        widget.onDecisionMade(ownership);
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // Prevent dismissal without decision
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: AppPallete.lightGrey,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.security, size: 48, color: AppPallete.primary),
            const SizedBox(height: 16),
            const Text(
              'Who needs help?',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'This helps us notify the right people.',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 32),
            // FIX: Modal now shows immediately. While the emergency id is being
            // fetched (GPS + API), display a connecting spinner with a message.
            // Once the id arrives via ValueNotifier, the choice buttons appear.
            // The user sees the modal in < 100ms instead of waiting 5-30 seconds.
            ValueListenableBuilder<int?>(
              valueListenable: widget.emergencyIdNotifier,
              builder: (context, emergencyId, _) {
                if (emergencyId == null || _isLoading) {
                  return Column(
                    children: const [
                      CircularProgressIndicator(color: Colors.white),
                      SizedBox(height: 12),
                      Text(
                        'Connecting & getting your location…',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ],
                  );
                }
                return Column(
                  children: [
                    _OptionButton(
                      label: 'Me (I need help)',
                      icon: Icons.person,
                      color: AppPallete.error,
                      onPressed: () => _makeDecision('SELF'),
                    ),
                    const SizedBox(height: 16),
                    _OptionButton(
                      label: "I'm helping someone else",
                      icon: Icons.people,
                      color: AppPallete.primary,
                      onPressed: () => _makeDecision('OTHER'),
                    ),
                    if (widget.onCancel != null) ...[
                      const SizedBox(height: 24),
                      OutlinedButton.icon(
                        onPressed: () {
                          context.pop();
                          widget.onCancel!();
                        },
                        icon: const Icon(Icons.close, color: Colors.white70),
                        label: const Text("CANCEL EMERGENCY",
                            style: TextStyle(color: Colors.white70)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.white24),
                          padding: const EdgeInsets.all(16),
                        ),
                      ),
                    ]
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            const Text(
              "If you don't choose within 100s, we will notify your contacts and dispatch automatically.",
              style: TextStyle(color: Colors.white38, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  const _OptionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        icon: Icon(icon, color: Colors.white),
        label: Text(
          label,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
