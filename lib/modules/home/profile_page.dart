import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart'; 
import 'package:firebase_storage/firebase_storage.dart'; 
import 'package:campuspulse/modules/booking/my_bookings_page.dart';
import 'package:campuspulse/modules/wallet/topup_page.dart';
import 'package:campuspulse/modules/home/infographic_page.dart'; 
import 'package:campuspulse/modules/home/policies_page.dart'; 

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final User? user = FirebaseAuth.instance.currentUser;
  final _formKey = GlobalKey<FormState>();

  final _studentIdController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _phoneController = TextEditingController();
  
  int _selectedBuffer = 15; 

  bool _isLoading = false;
  bool _isEditing = false;
  String? _photoUrl;

  @override
  void initState() {
    super.initState();
    _fetchUserData();
  }

  void _showFloatingSnackBar(String message, {Color? backgroundColor}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: backgroundColor ?? const Color(0xFF262562),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.only(bottom: 15, left: 20, right: 20), 
        elevation: 8,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _fetchUserData() async {
    if (user == null) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('Students').doc(user!.uid).get();
      if (doc.exists) {
        final data = doc.data()!;
        setState(() {
          _studentIdController.text = data['student_id'] ?? '';
          _fullNameController.text = data['full_name'] ?? '';
          _usernameController.text = data['username'] ?? '';
          _phoneController.text = data['phone_number'] ?? '';
          _photoUrl = data['photo_url'];
          _selectedBuffer = data['arrival_buffer'] ?? 15;
        });
      }
    } catch (e) {
      _showFloatingSnackBar("Error loading profile: $e", backgroundColor: Colors.red);
    }
  }

  Future<void> _updateProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      await FirebaseFirestore.instance.collection('Students').doc(user!.uid).update({
        'student_id': _studentIdController.text.trim(),
        'full_name': _fullNameController.text.trim(),
        'username': _usernameController.text.trim(),
        'phone_number': _phoneController.text.trim(),
        'arrival_buffer': _selectedBuffer, 
      });
      
      setState(() => _isEditing = false);
      _showFloatingSnackBar("Profile updated successfully!", backgroundColor: Colors.green);
    } catch (e) {
      _showFloatingSnackBar("Update failed: $e", backgroundColor: Colors.red);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showEnlargedImage() {
    if (_photoUrl == null || _photoUrl!.isEmpty) return;
    
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          alignment: Alignment.center,
          children: [
            InteractiveViewer(
              panEnabled: true,
              boundaryMargin: const EdgeInsets.all(20),
              minScale: 1,
              maxScale: 4,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Image.network(_photoUrl!, fit: BoxFit.contain),
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmLogout() async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text("Confirm Logout", style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text("Are you sure you want to log out of CampusPulse?", style: TextStyle(fontSize: 15)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context); 
              await FirebaseAuth.instance.signOut();
              if (mounted) Navigator.pushReplacementNamed(context, '/login');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF262562),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text("Logout"),
          ),
        ],
      ),
    );
  }

  void _showChangePasswordDialog() {
    final oldPassController = TextEditingController();
    final newPassController = TextEditingController();
    final confirmNewPassController = TextEditingController(); 
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.orange.shade50, shape: BoxShape.circle),
              child: Icon(Icons.lock_reset_rounded, color: Colors.orange.shade700),
            ),
            const SizedBox(width: 12),
            const Text("Change Password", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: Color(0xFF262562))),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Ensure your new password is at least 8 characters long with a mix of letters and numbers.", style: TextStyle(color: Colors.grey, fontSize: 13, height: 1.4)),
              const SizedBox(height: 20),
              _buildDialogTextField("Old Password", oldPassController, true, Icons.lock_outline),
              const SizedBox(height: 16),
              _buildDialogTextField("New Password", newPassController, true, Icons.lock_outline),
              const SizedBox(height: 16),
              _buildDialogTextField("Confirm Password", confirmNewPassController, true, Icons.check_circle_outline),
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        actions: [
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context), 
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: const Text("Cancel", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 16))
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF262562), 
                    foregroundColor: Colors.white, 
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 5,
                    shadowColor: const Color(0xFF262562).withOpacity(0.3)
                  ),
                  onPressed: () async {
                    if (newPassController.text != confirmNewPassController.text) {
                       _showFloatingSnackBar("New passwords do not match.", backgroundColor: Colors.red);
                       return;
                    }

                    final passRegex = RegExp(r'^(?=.*?[A-Z])(?=.*?[a-z])(?=.*?[0-9])(?=.*?[!@#\$&*~]).{8,}$');
                    if (!passRegex.hasMatch(newPassController.text)) {
                       _showFloatingSnackBar("Password must be 8+ chars, with Upper, Lower, Number & Special char.", backgroundColor: Colors.red);
                       return;
                    }

                    Navigator.pop(context); 
                    _performPasswordChange(oldPassController.text, newPassController.text);
                  },
                  child: const Text("Update", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildDialogTextField(String label, TextEditingController controller, bool obscure, IconData icon) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200, width: 1.5),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.w500),
          prefixIcon: Icon(icon, color: Colors.grey.shade400, size: 20),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    );
  }

  Future<void> _performPasswordChange(String oldPass, String newPass) async {
    setState(() => _isLoading = true);
    try {
      AuthCredential credential = EmailAuthProvider.credential(email: user!.email!, password: oldPass);
      await user!.reauthenticateWithCredential(credential);
      await user!.updatePassword(newPass);
      _showFloatingSnackBar("Password changed successfully!", backgroundColor: Colors.green);
    } on FirebaseAuthException catch (e) {
      String errorMessage = "Failed to change password.";
      if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        errorMessage = "The old password you entered is incorrect.";
      } else if (e.code == 'weak-password') {
        errorMessage = "The new password is too weak.";
      } else {
        errorMessage = "Error: ${e.message}";
      }
      _showFloatingSnackBar(errorMessage, backgroundColor: Colors.red);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showDeleteAccountDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text("Delete Account", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
          ],
        ),
        content: const Text("Are you sure you want to delete your account? This action is permanent and cannot be undone.", style: TextStyle(fontSize: 15)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: () async {
              Navigator.pop(context);
              _performDeleteAccount();
            },
            child: const Text("Delete"),
          ),
        ],
      ),
    );
  }

  Future<void> _performDeleteAccount() async {
    setState(() => _isLoading = true);
    try {
      if (_photoUrl != null && _photoUrl!.isNotEmpty) {
        try {
          await FirebaseStorage.instance.refFromURL(_photoUrl!).delete();
        } catch (e) {
          debugPrint("Error deleting image: $e");
        }
      }
      await FirebaseFirestore.instance.collection('Students').doc(user!.uid).delete();
      await user!.delete();
      if (mounted) Navigator.pushReplacementNamed(context, '/login');
    } catch (e) {
      _showFloatingSnackBar("Failed to delete. Try re-login. Error: $e", backgroundColor: Colors.red);
      setState(() => _isLoading = false);
    }
  }

  Future<void> _editProfilePicture() async {
    try {
      final ImagePicker picker = ImagePicker();
      
      // 1. Pick the raw image WITHOUT any native compression arguments.
      // Providing maxWidth/imageQuality causes Android's BitmapFactory to crash 
      // when it attempts to process Samsung Motion Photos or HEIC files.
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);
      
      if (image == null) return; 

      setState(() => _isLoading = true);

      // 2. Read the raw bytes into Dart memory.
      final Uint8List rawBytes = await image.readAsBytes();

      // 3. Force Flutter's Skia engine to safely decode and downscale the image.
      // This completely strips away EXIF data, trailing MP4 payloads (Motion Photos), 
      // and safely interprets HEIC structures into a raw 2D pixel array.
      final ui.Codec codec = await ui.instantiateImageCodec(
        rawBytes,
        targetWidth: 800, // Automatically scales height to maintain aspect ratio safely
      );
      
      final ui.FrameInfo frameInfo = await codec.getNextFrame();
      final ui.Image decodedImage = frameInfo.image;

      // 4. Re-encode the pure visual frame into a universally standard PNG byte stream.
      final ByteData? byteData = await decodedImage.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception("Failed to encode image to PNG");
      
      final Uint8List purePngBytes = byteData.buffer.asUint8List();

      // 5. Optimization: Delete the old photo first so Storage doesn't get bloated.
      if (_photoUrl != null && _photoUrl!.isNotEmpty) {
         try {
           await FirebaseStorage.instance.refFromURL(_photoUrl!).delete();
         } catch (e) {
           debugPrint("Ignored old storage delete error: $e");
         }
      }

      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();

      // Upload the strictly encoded PNG byte stream
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('profile_images')
          .child('${user!.uid}_$timestamp.png');

      // Set Cache-Control metadata for instant web cache bypass
      final metadata = SettableMetadata(
        contentType: 'image/png',
        cacheControl: 'public, max-age=0',
      );
      
      // Use putData to upload the raw bytes directly
      final TaskSnapshot snapshot = await storageRef.putData(purePngBytes, metadata);
      final downloadUrl = await snapshot.ref.getDownloadURL();

      await FirebaseFirestore.instance.collection('Students').doc(user!.uid).update({
        'photo_url': downloadUrl,
      });

      setState(() {
        _photoUrl = downloadUrl;
        _isLoading = false;
      });

      _showFloatingSnackBar("Profile picture updated!", backgroundColor: Colors.green);

    } catch (e) {
      setState(() => _isLoading = false);
      _showFloatingSnackBar("Failed to process image. Try a standard photo.", backgroundColor: Colors.red);
      debugPrint("Image upload error: $e");
    }
  }

  void _removeProfilePicture() async {
    setState(() => _isLoading = true);
    try {
      if (_photoUrl != null && _photoUrl!.isNotEmpty) {
         try {
           await FirebaseStorage.instance.refFromURL(_photoUrl!).delete();
         } catch (e) {
           debugPrint("Ignored storage delete error: $e");
         }
      }
      await FirebaseFirestore.instance.collection('Students').doc(user!.uid).update({'photo_url': ""});
      
      setState(() {
        _photoUrl = null;
        _isLoading = false;
      });
      _showFloatingSnackBar("Profile picture removed.", backgroundColor: Colors.green);
    } catch (e) {
      setState(() => _isLoading = false);
      _showFloatingSnackBar("Error removing photo: $e", backgroundColor: Colors.red);
    }
  }

  void _showPreferenceInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.auto_awesome_motion, color: Color(0xFF262562)),
            SizedBox(width: 10),
            Text("Arrival Preference", style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF262562), fontSize: 18, letterSpacing: -0.5)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Tell the Smart Planner how early you prefer to arrive before your physical classes begin.",
              style: TextStyle(fontSize: 14, color: Colors.black87, height: 1.5, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 16),
            _buildInfoRow(Icons.directions_run_rounded, "Just-in-time (5 min)", "For when you prefer arriving exactly as class starts."),
            _buildInfoRow(Icons.local_cafe_rounded, "Early Bird (30 min)", "Great for grabbing a coffee or catching up on notes before class."),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF262562),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
              ),
              child: const Text("Got it", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: const Color(0xFFF0AB00)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF262562))),
                Text(desc, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ],
            ),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA), 
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        toolbarHeight: 60,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: _isLoading 
              ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF262562))))
              : TextButton.icon(
                  onPressed: () {
                    if (_isEditing) {
                      _updateProfile();
                    } else {
                      setState(() => _isEditing = true);
                    }
                  },
                  icon: Icon(_isEditing ? Icons.check_circle : Icons.edit, color: const Color(0xFF262562), size: 18),
                  label: Text(_isEditing ? "Save" : "Edit", style: const TextStyle(color: Color(0xFF262562), fontWeight: FontWeight.bold, fontSize: 16)),
                  style: TextButton.styleFrom(
                    backgroundColor: const Color(0xFF262562).withOpacity(0.1),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))
                  ),
                ),
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: _photoUrl != null && _photoUrl!.isNotEmpty ? _showEnlargedImage : null,
                child: Stack(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(color: const Color(0xFF262562).withOpacity(0.15), blurRadius: 20, offset: const Offset(0, 10))
                        ],
                      ),
                      child: CircleAvatar(
                        radius: 60,
                        backgroundColor: Colors.grey.shade100,
                        backgroundImage: _photoUrl != null && _photoUrl!.isNotEmpty ? NetworkImage(_photoUrl!) : null,
                        child: _photoUrl == null || _photoUrl!.isEmpty 
                          ? Icon(Icons.person_rounded, size: 60, color: Colors.grey.shade400) 
                          : null,
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 4,
                      child: GestureDetector(
                        onTap: _editProfilePicture,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0AB00), 
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2))]
                          ),
                          child: const Icon(Icons.camera_alt, size: 18, color: Colors.white),
                        ),
                      ),
                    )
                  ],
                ),
              ),
              
              if (_photoUrl != null && _photoUrl!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: GestureDetector(
                    onTap: _removeProfilePicture,
                    child: const Text("Remove Photo", style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600, fontSize: 13)),
                  ),
                ),

              const SizedBox(height: 30),

              // --- Section 1: Personal Information ---
              const Align(alignment: Alignment.centerLeft, child: Text("Personal Info", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey))),
              const SizedBox(height: 12),
              
              _buildModernTextField("Full Name", _fullNameController, Icons.person, enabled: _isEditing, validator: (val) => val!.isEmpty ? "Cannot be empty" : null),
              _buildModernTextField("Student ID", _studentIdController, Icons.badge, enabled: _isEditing, isNumeric: true, validator: (val) => RegExp(r'^[0-9]{12}$').hasMatch(val!) ? "ID must be 11 digits" : null),
              _buildModernTextField("Username", _usernameController, Icons.alternate_email, enabled: _isEditing, hint: "Display name for greeting"),
              _buildModernTextField("Phone", _phoneController, Icons.phone, enabled: _isEditing, isNumeric: true, validator: (val) => RegExp(r'^(\+?60|0)[0-9]{1,2}-?[0-9]{7,8}$').hasMatch(val!) ? null : "Invalid format"),
              
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(20)),
                child: Row(
                  children: [
                    Icon(Icons.email, color: Colors.grey.shade500),
                    const SizedBox(width: 16),
                    Expanded(child: Text(user?.email ?? "No email", style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w600, fontSize: 16))),
                    const Icon(Icons.lock_outline, color: Colors.grey, size: 18),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              Row(
                children: [
                  const Text("Smart Planner Preference", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => _showPreferenceInfoDialog(context),
                    child: const Icon(Icons.info_outline_rounded, size: 18, color: Colors.grey),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildBufferSelector(),
              
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50, 
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade100)
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline_rounded, size: 18, color: Colors.blue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Note: By default, the system applies a standard 15-minute buffer. Tap a selected option again to deselect and return to the default.",
                        style: TextStyle(color: Colors.blue.shade800, fontSize: 12, fontWeight: FontWeight.w600, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 30),

              // --- Section 2: Preferences & Security ---
              const Align(alignment: Alignment.centerLeft, child: Text("Preferences", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey))),
              const SizedBox(height: 12),

              _buildSettingsCard(
                title: "My Bookings History",
                icon: Icons.history_edu,
                color: const Color(0xFF262562),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyBookingsPage())),
              ),
              const SizedBox(height: 12),
              _buildSettingsCard(
                title: "Campus Credits",
                icon: Icons.account_balance_wallet,
                color: const Color(0xFFF0AB00),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TopUpPage())),
              ),
              const SizedBox(height: 12),
              _buildSettingsCard(
                title: "Change Password",
                icon: Icons.lock_reset,
                color: Colors.orange.shade700,
                onTap: _showChangePasswordDialog,
              ),
              
              const SizedBox(height: 12),
              _buildSettingsCard(
                title: "User Guide & Tutorial",
                icon: Icons.help_outline_rounded,
                color: Colors.blue.shade600,
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const InfographicPage()));
                },
              ),

              const SizedBox(height: 30),

              // --- NEW: Legal & Policies Hub ---
              const Align(alignment: Alignment.centerLeft, child: Text("Legal & Policies", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey))),
              const SizedBox(height: 12),
              
              _buildSettingsCard(
                title: "Rules & Regulations",
                icon: Icons.gavel_rounded,
                color: Colors.teal.shade600,
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const PoliciesPage()));
                },
              ),

              const SizedBox(height: 30),

              // --- Section 3: Danger Zone ---
              const Align(alignment: Alignment.centerLeft, child: Text("Account Actions", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.redAccent))),
              const SizedBox(height: 12),
              
              _buildSettingsCard(
                title: "Logout",
                icon: Icons.logout,
                color: Colors.red,
                isDestructive: true,
                onTap: _confirmLogout,
              ),
              const SizedBox(height: 12),
              _buildSettingsCard(
                title: "Delete Account",
                icon: Icons.delete_forever,
                color: Colors.red,
                isDestructive: true,
                onTap: _showDeleteAccountDialog,
              ),

              const SizedBox(height: 120), 
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBufferSelector() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          _buildBufferOption("Just-in-time", "5 min", 5),
          _buildBufferOption("Early Bird", "30 min", 30),
        ],
      ),
    );
  }

  Widget _buildBufferOption(String title, String subtitle, int value) {
    bool isSelected = _selectedBuffer == value;
    return Expanded(
      child: GestureDetector(
        onTap: _isEditing ? () => setState(() => _selectedBuffer = (_selectedBuffer == value) ? 15 : value) : () => _showFloatingSnackBar("Tap 'Edit' to change your preferences.", backgroundColor: Colors.orange),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF262562) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Text(title, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isSelected ? Colors.white70 : Colors.grey)),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: isSelected ? Colors.white : Colors.black87)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModernTextField(String label, TextEditingController controller, IconData icon, {
    bool enabled = true, 
    bool isNumeric = false, 
    String? Function(String?)? validator,
    String? hint
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))
        ],
        border: Border.all(color: _isEditing ? const Color(0xFF262562).withOpacity(0.4) : Colors.transparent, width: 1.5),
      ),
      child: TextFormField(
        controller: controller,
        enabled: enabled,
        keyboardType: isNumeric ? TextInputType.number : TextInputType.text,
        validator: validator,
        style: TextStyle(color: enabled ? Colors.black87 : Colors.grey.shade800, fontWeight: FontWeight.w600, fontSize: 16),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.w500),
          hintText: hint,
          prefixIcon: Icon(icon, color: _isEditing ? const Color(0xFF262562) : Colors.grey.shade400),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        ),
      ),
    );
  }

  Widget _buildSettingsCard({
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDestructive ? Colors.red.withOpacity(0.1) : color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title, 
                style: TextStyle(
                  color: isDestructive ? Colors.red : Colors.black87, 
                  fontSize: 16, 
                  fontWeight: FontWeight.w700
                )
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }
}