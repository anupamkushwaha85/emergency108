import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../emergency/data/emergency_repository.dart';

// ─── Data class for dropdown options ───────────────────────────────────────────
class _EmergencyOption {
  final String scenario;
  final String label;
  final IconData icon;
  final Color color;

  const _EmergencyOption(this.scenario, this.label, this.icon, this.color);
}

// ─── Screen ────────────────────────────────────────────────────────────────────
class AiFirstAidScreen extends ConsumerStatefulWidget {
  final int? emergencyId;

  const AiFirstAidScreen({super.key, this.emergencyId});

  @override
  ConsumerState<AiFirstAidScreen> createState() => _AiFirstAidScreenState();
}

class _AiFirstAidScreenState extends ConsumerState<AiFirstAidScreen> {
  final List<Message> _messages = [];
  final ScrollController _scrollController = ScrollController();
  bool _showInput = true;
  bool _isTyping = false;
  String? _selectedScenario;

  static const List<_EmergencyOption> _options = [
    _EmergencyOption(
      'unconscious',
      'Patient is unconscious',
      Icons.emergency_rounded,
      Color(0xFFD32F2F),
    ),
    _EmergencyOption(
      'bleeding',
      'Heavy bleeding from wound',
      Icons.water_drop_rounded,
      Color(0xFFE65100),
    ),
    _EmergencyOption(
      'choking',
      'Someone is choking',
      Icons.air_rounded,
      Color(0xFFF57F17),
    ),
    _EmergencyOption(
      'chest_pain',
      'Chest pain / Heart attack',
      Icons.favorite_rounded,
      Color(0xFFC62828),
    ),
    _EmergencyOption(
      'seizure',
      'Person having seizure',
      Icons.warning_amber_rounded,
      Color(0xFF6A1B9A),
    ),
    _EmergencyOption(
      'burn',
      'Severe burn / fire injury',
      Icons.local_fire_department_rounded,
      Color(0xFFBF360C),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _addAiMessage(
      "👋 Hello! I'm your AI First Aid Assistant.\n\n"
      "I'll guide you step by step through the emergency. "
      "Please select what's happening using the dropdown below.",
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // ─── Message helpers ──────────────────────────────────────────────────────────

  void _addAiMessage(String text, {String? gifPath}) {
    setState(() {
      _messages.add(Message(text: text, isUser: false, gifPath: gifPath));
    });
    _scrollToBottom();
  }

  void _addMessage(Message message) {
    setState(() => _messages.add(message));
    _scrollToBottom();
    if (message.isUser) _processUserResponse(message.text, message.scenarioType);
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 120), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ─── Logic ────────────────────────────────────────────────────────────────────

  Future<void> _processUserResponse(String text, String? scenarioType) async {
    setState(() {
      _showInput = false;
      _isTyping = true;
    });

    if (widget.emergencyId != null && scenarioType != null) {
      try {
        await ref.read(emergencyRepositoryProvider).updateAiAssessment(
          widget.emergencyId!,
          assessment: 'Emergency Scenario: $text',
          triage: {'scenario': scenarioType},
        );
      } catch (e) {
        debugPrint('Backend sync failed: $e');
      }
    }

    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;

    setState(() => _isTyping = false);
    _addAiMessage(
      _getResponseText(scenarioType),
      gifPath: scenarioType == 'unconscious' ? 'assets/gifs/cpr_instructions.gif' : null,
    );
  }

  void _sendSelected() {
    if (_selectedScenario == null) return;
    final opt = _options.firstWhere((o) => o.scenario == _selectedScenario);
    _addMessage(Message(text: opt.label, isUser: true, scenarioType: opt.scenario));
    setState(() => _selectedScenario = null);
  }

  // ─── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEFEFEF),
      appBar: _buildAppBar(),
      body: Column(
        children: [
          Expanded(child: _buildChatList()),
          if (_isTyping) _buildTypingIndicator(),
          if (_showInput) _buildInputArea(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 1,
      shadowColor: const Color(0x1A000000),
      surfaceTintColor: Colors.white,
      automaticallyImplyLeading: false,
      titleSpacing: 16,
      title: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: Color(0xFFFFEBEB),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.medical_services_rounded,
              color: Color(0xFFFF2B2B),
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'AI First Aid Assistant',
                style: TextStyle(
                  color: Color(0xFF1A1A1A),
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              SizedBox(height: 2),
              Row(
                children: [
                  Icon(Icons.circle, color: Color(0xFF4CAF50), size: 8),
                  SizedBox(width: 5),
                  Text(
                    'Always available · 24/7',
                    style: TextStyle(color: Color(0xFF888888), fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChatList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      itemCount: _messages.length,
      itemBuilder: (context, index) => _buildBubble(_messages[index]),
    );
  }

  Widget _buildBubble(Message msg) {
    final isUser = msg.isUser;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // AI avatar
          if (!isUser) ...[
            Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(
                color: Color(0xFFFFEBEB),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.medical_services_rounded,
                size: 17,
                color: Color(0xFFFF2B2B),
              ),
            ),
            const SizedBox(width: 8),
          ],

          // Bubble
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.73,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: isUser ? const Color(0xFFFF2B2B) : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isUser ? 18 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 18),
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (msg.gifPath != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.asset(
                        msg.gifPath!,
                        width: double.infinity,
                        height: 160,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: double.infinity,
                          height: 100,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.play_circle_outline,
                            size: 36,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  Text(
                    msg.text,
                    style: TextStyle(
                      color: isUser ? Colors.white : const Color(0xFF1A1A1A),
                      fontSize: 14.5,
                      height: 1.55,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Right spacer for AI messages (keeps AI bubbles left-aligned)
          if (!isUser) const SizedBox(width: 42),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 4, top: 2),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(
              color: Color(0xFFFFEBEB),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.medical_services_rounded,
              size: 17,
              color: Color(0xFFFF2B2B),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
                bottomRight: Radius.circular(18),
                bottomLeft: Radius.circular(4),
              ),
              boxShadow: [
                BoxShadow(color: Color(0x14000000), blurRadius: 4),
              ],
            ),
            child: const _TypingDots(),
          ),
        ],
      ),
    );
  }

  // ─── Input area ───────────────────────────────────────────────────────────────

  Widget _buildInputArea() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE8E8E8))),
        boxShadow: [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 12,
            offset: Offset(0, -3),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Label row
          const Row(
            children: [
              Icon(Icons.touch_app_rounded, size: 18, color: Color(0xFFFF2B2B)),
              SizedBox(width: 8),
              Text(
                "What's the emergency?",
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A1A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Select the type closest to your situation',
            style: TextStyle(fontSize: 12, color: Color(0xFF888888)),
          ),
          const SizedBox(height: 14),

          // Styled dropdown
          DropdownButtonFormField<String>(
            value: _selectedScenario,
            icon: const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Color(0xFF555555),
            ),
            isExpanded: true,
            hint: const Text(
              'Tap to select situation…',
              style: TextStyle(color: Color(0xFFAAAAAA), fontSize: 14),
            ),
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFFF7F7F7),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFFF2B2B), width: 1.5),
              ),
            ),
            dropdownColor: Colors.white,
            borderRadius: BorderRadius.circular(12),
            items: _options.map((opt) {
              return DropdownMenuItem<String>(
                value: opt.scenario,
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: opt.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(opt.icon, color: opt.color, size: 19),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        opt.label,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF1A1A1A),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
            onChanged: (val) => setState(() => _selectedScenario = val),
          ),

          const SizedBox(height: 12),

          // Send button
          ElevatedButton.icon(
            onPressed: _selectedScenario != null ? _sendSelected : null,
            icon: const Icon(Icons.send_rounded, size: 18),
            label: const Text(
              'Get First Aid Instructions',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF2B2B),
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFE8E8E8),
              disabledForegroundColor: const Color(0xFFAAAAAA),
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }

  // ─── AI response content ──────────────────────────────────────────────────────

  String _getResponseText(String? scenarioType) {
    switch (scenarioType) {
      case 'unconscious':
        return "⚠️ CRITICAL — Unconscious Patient:\n\n"
            "1️⃣ Check if they're breathing\n"
            "   • Look for chest movement\n"
            "   • Listen for breathing sounds\n\n"
            "2️⃣ If NOT breathing:\n"
            "   • Lay them flat on back\n"
            "   • Place hands center of chest\n"
            "   • Push hard & fast (100–120/min)\n"
            "   • Continue until ambulance arrives\n\n"
            "3️⃣ If breathing:\n"
            "   • Place in recovery position\n"
            "   • Monitor constantly\n\n"
            "Help is coming. Don't leave them alone! 🚨";

      case 'bleeding':
        return "🩸 Heavy Bleeding Protocol:\n\n"
            "1️⃣ Apply FIRM direct pressure\n"
            "   • Use clean cloth or gauze\n"
            "   • Press down hard on wound\n\n"
            "2️⃣ If cloth soaks through:\n"
            "   • DO NOT remove it\n"
            "   • Add more cloth on top\n"
            "   • Keep pressing firmly\n\n"
            "3️⃣ If possible:\n"
            "   • Elevate wound above heart level\n"
            "   • Lay the patient down\n\n"
            "Ambulance is on the way 🚑";

      case 'choking':
        return "😷 Choking Emergency:\n\n"
            "1️⃣ Can they cough or speak?\n"
            "   • If YES → Encourage strong coughing\n"
            "   • If NO → Proceed to step 2\n\n"
            "2️⃣ Perform 5 back blows:\n"
            "   • Lean them forward\n"
            "   • Sharp blows between shoulder blades\n\n"
            "3️⃣ If still not working:\n"
            "   • Stand behind them\n"
            "   • Perform abdominal thrusts (Heimlich)\n\n"
            "4️⃣ Alternate 5 back blows → 5 thrusts\n\n"
            "Keep going until object comes out! 💪";

      case 'chest_pain':
        return "💔 Chest Pain — Heart Attack Protocol:\n\n"
            "1️⃣ Immediately:\n"
            "   • Sit them down, keep them still\n"
            "   • Loosen tight clothing\n"
            "   • Keep them calm\n\n"
            "2️⃣ If conscious:\n"
            "   • Ask if they carry heart medication\n"
            "   • Help them take it if prescribed\n\n"
            "3️⃣ Monitor:\n"
            "   • Watch for breathing changes\n"
            "   • Check consciousness regularly\n\n"
            "4️⃣ DO NOT:\n"
            "   • Give food or water\n"
            "   • Let them walk around\n\n"
            "Ambulance is rushing to you! 🚨";

      case 'seizure':
        return "⚡ Seizure Emergency:\n\n"
            "1️⃣ Protect them:\n"
            "   • Clear space around them\n"
            "   • Move dangerous objects away\n"
            "   • Cushion their head\n\n"
            "2️⃣ DO NOT:\n"
            "   • Hold them down\n"
            "   • Put anything in mouth\n"
            "   • Give water\n\n"
            "3️⃣ After seizure:\n"
            "   • Place in recovery position\n"
            "   • Stay with them\n"
            "   • Note how long it lasted\n\n"
            "Help is arriving! Stay calm 🚑";

      case 'burn':
        return "🔥 Burn Treatment:\n\n"
            "1️⃣ Stop the burning:\n"
            "   • Remove from heat source\n"
            "   • Remove jewelry / tight clothing\n\n"
            "2️⃣ Cool the burn:\n"
            "   • Run under cool water 10–20 min\n"
            "   • DO NOT use ice\n\n"
            "3️⃣ Cover the burn:\n"
            "   • Use clean, dry cloth\n"
            "   • DO NOT apply creams or butter\n\n"
            "4️⃣ For severe burns:\n"
            "   • DO NOT remove stuck clothing\n"
            "   • Keep the patient warm\n\n"
            "Medical help is coming! 🚨";

      default:
        return "I'm here to help! Can you tell me more:\n\n"
            "• Is the patient conscious?\n"
            "• Are they breathing normally?\n"
            "• Is there visible injury or bleeding?\n"
            "• Any chest pain or difficulty breathing?\n\n"
            "Stay calm — help is on the way! 💪";
    }
  }
}

// ─── Animated typing indicator (three bouncing dots) ─────────────────────────

class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final phase = ((_ctrl.value * 3 - i) % 1.0).clamp(0.0, 1.0);
            final opacity = 0.3 + 0.7 * (1.0 - (phase * 2 - 1.0).abs());
            return Padding(
              padding: EdgeInsets.only(right: i < 2 ? 5 : 0),
              child: Opacity(
                opacity: opacity,
                child: const CircleAvatar(
                  radius: 4,
                  backgroundColor: Color(0xFFAAAAAA),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

// ─── Message model ─────────────────────────────────────────────────────────────

class Message {
  final String text;
  final bool isUser;
  final String? scenarioType;
  final String? gifPath;

  Message({
    required this.text,
    required this.isUser,
    this.scenarioType,
    this.gifPath,
  });
}

