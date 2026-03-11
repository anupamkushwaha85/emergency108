import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';


class DriverAppBar extends StatelessWidget {
  final VoidCallback onLogout;

  const DriverAppBar({super.key, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Profile Icon (Top Left)
          GestureDetector(
            onTap: () => context.push('/profile'),
            child: CircleAvatar(
              radius: 24,
              backgroundColor: Colors.white.withOpacity(0.2),
              child: const Icon(Icons.person, color: Colors.white, size: 28),
            ),
          ),
          
          // App Title (Top Center)
          Text(
            'Driver Console',
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          
          // Custom Menu Icon (Top Right)
          PopupMenuButton<String>(
            color: Colors.white,
            offset: const Offset(0, 50),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            child: Container(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                   _buildHollowDot(),
                   const SizedBox(height: 3),
                   _buildHollowDot(),
                   const SizedBox(height: 3),
                   _buildHollowDot(),
                ],
              ),
            ),
            itemBuilder: (context) => [
               const PopupMenuItem(value: 'logout', child: Text('Logout')),
            ],
            onSelected: (value) async {
               if (value == 'logout') {
                 onLogout();
               }
            },
          ),
        ],
      ),
    );
  }
  
  Widget _buildHollowDot() {
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
        color: Colors.transparent,
      ),
    );
  }
}
