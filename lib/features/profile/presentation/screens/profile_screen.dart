import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:emergency108_app/core/theme/app_theme.dart';
import 'package:emergency108_app/features/profile/data/profile_repository.dart';
import 'package:emergency108_app/features/location/presentation/screens/location_permission_screen.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  String _selectedGender = 'Male';
  DateTime? _selectedDOB;
  String _selectedBloodGroup = 'Select';
  bool _isLoading = false;
  
  final List<String> _bloodGroups = [
    'Select',
    'A+',
    'A-',
    'B+',
    'B-',
    'AB+',
    'AB-',
    'O+',
    'O-',
  ];

  bool _isEditing = true;
  bool _isProfileComplete = false;

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  Future<void> _loadProfileData() async {
    final profile = await ref.read(profileRepositoryProvider).getUserProfile();
    final name = profile['name'] ?? '';
    if (name.isNotEmpty) {
      setState(() {
        _nameController.text = name;
        _addressController.text = profile['address'] ?? '';
        _selectedGender = profile['gender'] ?? 'Male';
        final dobStr = profile['dob'];
        if (dobStr != null && dobStr.isNotEmpty) {
          try {
            _selectedDOB = DateFormat('yyyy-MM-dd').parse(dobStr);
          } catch(e) {}
        }
        _selectedBloodGroup = profile['bloodGroup'] ?? 'Select';
        _isProfileComplete = true;
        _isEditing = false;
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context) async {
    if (!_isEditing) return;
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().subtract(const Duration(days: 365 * 25)),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFFE60D11),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black87,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDOB) {
      setState(() {
        _selectedDOB = picked;
      });
    }
  }

  void _saveDetails() async {
    // Validation
    if (_nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your name')),
      );
      return;
    }
    if (_addressController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your address')),
      );
      return;
    }
    if (_selectedDOB == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select your date of birth')),
      );
      return;
    }
    
    setState(() => _isLoading = true);
    
    try {
      // Calculate age from DOB
      final now = DateTime.now();
      int age = now.year - _selectedDOB!.year;
      if (now.month < _selectedDOB!.month || 
          (now.month == _selectedDOB!.month && now.day < _selectedDOB!.day)) {
        age--;
      }
      
      // Format DOB as yyyy-MM-dd
      final dobString = DateFormat('yyyy-MM-dd').format(_selectedDOB!);
      
      // Call API
      await ref.read(profileRepositoryProvider).updateProfile(
        name: _nameController.text,
        address: _addressController.text,
        gender: _selectedGender,
        dateOfBirth: dobString,
        age: age,
        bloodGroup: _selectedBloodGroup != 'Select' ? _selectedBloodGroup : null,
      );
      
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile saved successfully!'),
          backgroundColor: Colors.green,
        ),
      );
      
      // Navigate to location permission screen
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => const LocationPermissionScreen(),
        ),
      );
      
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: AppTheme.backgroundGradient,
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 20),
                  
                  // Top action bar
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Back button if needed, or empty space
                      if (GoRouter.of(context).canPop())
                        IconButton(
                           icon: const Icon(Icons.arrow_back, color: Colors.black87),
                           onPressed: () => context.pop(),
                        )
                      else
                        const SizedBox(width: 48),

                      if (_isProfileComplete)
                        IconButton(
                          icon: Icon(
                            _isEditing ? Icons.close : Icons.edit,
                            color: Colors.black87,
                          ),
                          onPressed: () {
                            setState(() {
                              _isEditing = !_isEditing;
                            });
                          },
                        )
                      else
                        const SizedBox(width: 48),
                    ],
                  ),
                  
                  // Title
                Text(
                  'Set Up Your Profile',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                
                const SizedBox(height: 8),
                
                // Subtitle
                Text(
                  'This helps doctors and emergency\nresponders identify you',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: Colors.black54,
                  ),
                ),
                
                const SizedBox(height: 40),
                
                // Full Name Label
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Full Name',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ),
                
                const SizedBox(height: 8),
                
                // Full Name Input
                TextField(
                  controller: _nameController,
                  enabled: _isEditing,
                  textInputAction: TextInputAction.next,
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    color: _isEditing ? Colors.black87 : Colors.black54,
                  ),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.7),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: Colors.black.withOpacity(0.2),
                        width: 1,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: Colors.black.withOpacity(0.2),
                        width: 1,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                        color: Colors.black,
                        width: 1.5,
                      ),
                    ),
                    disabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: Colors.black.withOpacity(0.1),
                        width: 1,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Address Label
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Address',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ),
                
                const SizedBox(height: 8),
                
                // Address Input
                TextField(
                  controller: _addressController,
                  enabled: _isEditing,
                  textInputAction: TextInputAction.done,
                  maxLines: 2,
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    color: _isEditing ? Colors.black87 : Colors.black54,
                  ),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.7),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: Colors.black.withOpacity(0.2),
                        width: 1,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: Colors.black.withOpacity(0.2),
                        width: 1,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                        color: Colors.black,
                        width: 1.5,
                      ),
                    ),
                    disabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: Colors.black.withOpacity(0.1),
                        width: 1,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Gender Label
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Gender',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ),
                
                const SizedBox(height: 12),
                
                // Gender Radio Buttons
                Row(
                  children: [
                    _buildGenderOption('Male'),
                    const SizedBox(width: 20),
                    _buildGenderOption('Female'),
                    const SizedBox(width: 20),
                    _buildGenderOption('Other'),
                  ],
                ),
                
                const SizedBox(height: 24),
                
                // Date of Birth Label
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Date of Birth',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ),
                
                const SizedBox(height: 8),
                
                // Date of Birth Selector
                GestureDetector(
                  onTap: () => _selectDate(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.black.withOpacity(0.2),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _selectedDOB == null
                              ? 'Select Date'
                              : DateFormat('dd/MM/yyyy').format(_selectedDOB!),
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            color: _selectedDOB == null
                                ? Colors.black38
                                : Colors.black87,
                          ),
                        ),
                        Icon(
                          Icons.calendar_today,
                          color: Colors.black.withOpacity(0.6),
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Blood Group Label
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Blood Group',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ),
                
                const SizedBox(height: 8),
                
                // Blood Group Dropdown
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.black.withOpacity(0.2),
                      width: 1,
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedBloodGroup,
                      isExpanded: true,
                      icon: Icon(
                        Icons.arrow_drop_down,
                        color: Colors.black.withOpacity(0.6),
                      ),
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        color: Colors.black87,
                      ),
                      dropdownColor: Colors.white,
                      items: _bloodGroups.map((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(
                            value,
                            style: GoogleFonts.inter(
                              color: value == 'Select'
                                  ? Colors.black38
                                  : Colors.black87,
                            ),
                          ),
                        );
                      }).toList(),
                      onChanged: _isEditing ? (String? newValue) {
                        setState(() {
                          _selectedBloodGroup = newValue!;
                        });
                      } : null,
                    ),
                  ),
                ),
                
                const SizedBox(height: 50),
                
                // Save Details Button (only shown if editing)
                if (_isEditing)
                  Center(
                  child: GestureDetector(
                    onTap: _isLoading ? null : _saveDetails,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 50,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: _isLoading
                              ? [Colors.grey, Colors.grey]
                              : const [
                                  Color(0xFFF5E5E5),
                                  Color(0xFFE60D11),
                                  Color(0xFFC80000),
                                  Color(0xFFE21F22),
                                  Color(0xFFF5E5E5),
                                ],
                          stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
                        ),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: Colors.black, width: 2),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              'Save Details',
                              style: GoogleFonts.inter(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                ),
                
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildGenderOption(String gender) {
    final isSelected = _selectedGender == gender;
    return GestureDetector(
      onTap: _isEditing ? () {
        setState(() {
          _selectedGender = gender;
        });
      } : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.black87,
                width: 2,
              ),
              color: isSelected ? Colors.black87 : Colors.transparent,
            ),
            child: isSelected
                ? const Center(
                    child: Icon(
                      Icons.circle,
                      size: 10,
                      color: Colors.white,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 6),
          Text(
            gender,
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}
