import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';
import '../../data/driver_repository.dart';
import '../../../../core/theme/app_theme.dart';

class VerificationPendingView extends ConsumerStatefulWidget {
  final String verificationStatus;

  const VerificationPendingView({super.key, required this.verificationStatus});

  @override
  ConsumerState<VerificationPendingView> createState() => _VerificationPendingViewState();
}

class _VerificationPendingViewState extends ConsumerState<VerificationPendingView> {
  final ImagePicker _picker = ImagePicker();
  XFile? _selectedImage;
  bool _isLoading = false;

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        imageQuality: 50,
        maxWidth: 1024,
      );

      if (image != null) {
        final bytes = await image.readAsBytes();
        final sizeInKb = bytes.lengthInBytes / 1024;

        if (sizeInKb > 500) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('File too large (${sizeInKb.toStringAsFixed(0)}KB). Max 500KB.')),
            );
          }
          return;
        }

        setState(() {
          _selectedImage = image;
        });
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not access ${source == ImageSource.camera ? "camera" : "gallery"}: $e')),
        );
      }
    }
  }

  void _showPickerOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Text('Select Document Source',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFFFEEEE),
                  child: Icon(Icons.camera_alt, color: Color(0xFFE60D11)),
                ),
                title: const Text('Take a Photo'),
                subtitle: const Text('Use camera to photograph your document'),
                onTap: () { Navigator.pop(ctx); _pickImage(ImageSource.camera); },
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFEEF4FF),
                  child: Icon(Icons.photo_library, color: Colors.blueAccent),
                ),
                title: const Text('Choose from Gallery'),
                subtitle: const Text('Select an existing photo'),
                onTap: () { Navigator.pop(ctx); _pickImage(ImageSource.gallery); },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _uploadDocument() async {
    if (_selectedImage == null) return;

    setState(() => _isLoading = true);

    try {
      final bytes = await _selectedImage!.readAsBytes();
      // Prefix with data URI scheme for easy rendering in web/admin
      final base64String = 'data:image/jpeg;base64,${base64Encode(bytes)}';
      
      await ref.read(driverRepositoryProvider).uploadDocument(base64String);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Document uploaded successfully! Waiting for approval.'),
            backgroundColor: Colors.green,
          ),
        );
        setState(() {
           _selectedImage = null;
        });
        
        // Refresh the app's state to reflect the PENDING status instead of missing/rejected.
        // The driver layout or router will fetch the new status on rebuild.
        // An easy way to force a fresh fetch is to just pop and push the branch again, 
        // or since it's a GoRouter setup, potentially just calling refresh() if auth provider handles it.
        // As a safe fallback, push a quick replacement to reload the widget tree.
        ref.invalidate(driverRepositoryProvider); // Invalidate provider if caching is used
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            // This forces a rebuild of the shell route / bottom nav ensuring a fresh status fetch
            context.go('/driver/home'); 
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: ${e.toString().replaceAll("Exception: ", "")}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isActionRequired = widget.verificationStatus != 'PENDING' && widget.verificationStatus != 'VERIFIED';

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Container(
          padding: const EdgeInsets.all(32.0),
          decoration: BoxDecoration(
            color: AppTheme.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryRed.withOpacity(0.1),
                blurRadius: 30,
                offset: const Offset(0, 10),
              )
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
               Icon(
                 isActionRequired ? Icons.warning_amber_rounded : Icons.verified_user_outlined,
                 size: 72, 
                 color: isActionRequired ? Colors.amber[700] : AppTheme.primaryRed,
               ),
               const SizedBox(height: 24),
               
               Text(
                 isActionRequired ? 'Action Required' : 'Verification Pending',
                 style: GoogleFonts.poppins(
                   color: AppTheme.black, 
                   fontSize: 24, 
                   fontWeight: FontWeight.w700,
                   letterSpacing: -0.5,
                 ),
                 textAlign: TextAlign.center,
               ),
               const SizedBox(height: 12),
               
               Text(
                  isActionRequired 
                      ? "Please upload a clear photo of your driving license or state ID to proceed."
                      : "Your account is currently under review by our administration team. Please check back shortly.",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    color: Colors.black54, 
                    fontSize: 15,
                    height: 1.5,
                  ),
               ),
               
               const SizedBox(height: 32),
               
               // Image Preview Area
               if (_selectedImage != null)
                 Container(
                   height: 200,
                   width: double.infinity,
                   margin: const EdgeInsets.only(bottom: 24),
                   decoration: BoxDecoration(
                     borderRadius: BorderRadius.circular(16),
                     border: Border.all(color: Colors.black12, width: 2),
                     image: DecorationImage(
                       image: FileImage(File(_selectedImage!.path)),
                       fit: BoxFit.cover,
                     ),
                     boxShadow: const [
                       BoxShadow(
                         color: Colors.black12,
                         blurRadius: 10,
                         offset: Offset(0, 4),
                       )
                     ]
                   ),
                   child: Stack(
                     children: [
                       Positioned(
                         top: 8, right: 8,
                         child: IconButton(
                           style: IconButton.styleFrom(
                             backgroundColor: Colors.white.withOpacity(0.8),
                           ),
                           icon: const Icon(Icons.close, color: Colors.black),
                           onPressed: () => setState(() => _selectedImage = null),
                         ),
                       )
                     ],
                   ),
                 ),

               // Action Buttons
               if (_isLoading)
                 CircularProgressIndicator(color: AppTheme.primaryRed)
               else 
                 Column(
                   crossAxisAlignment: CrossAxisAlignment.stretch,
                   children: [
                     if (_selectedImage == null && isActionRequired)
                       ElevatedButton.icon(
                         onPressed: _showPickerOptions,
                         icon: Icon(Icons.add_a_photo, color: AppTheme.primaryRed),
                         label: const Text('Select Document'),
                         style: ElevatedButton.styleFrom(
                           backgroundColor: AppTheme.white, 
                           foregroundColor: AppTheme.black,
                           elevation: 0,
                           shape: RoundedRectangleBorder(
                             borderRadius: BorderRadius.circular(16),
                             side: const BorderSide(color: Colors.black12, width: 2),
                           ),
                           padding: const EdgeInsets.symmetric(vertical: 16),
                         ),
                       ),

                     if (_selectedImage != null)
                       ElevatedButton(
                         onPressed: _uploadDocument,
                         style: ElevatedButton.styleFrom(
                           padding: const EdgeInsets.symmetric(vertical: 16),
                           shape: RoundedRectangleBorder(
                             borderRadius: BorderRadius.circular(16),
                           ),
                         ),
                         child: const Text('Submit Document'),
                       ),
                       
                     if (isActionRequired) ...[
                       const SizedBox(height: 16),
                       const Text(
                         "Max size: 500KB\nFormats: JPG, PNG",
                         textAlign: TextAlign.center,
                         style: TextStyle(color: Colors.black38, fontSize: 13, height: 1.4),
                       ),
                     ]
                   ],
                 ),
            ],
          ),
        ),
      ),
    );
  }
}
