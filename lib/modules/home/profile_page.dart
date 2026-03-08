import 'dart:io'; 
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart'; 
import 'package:firebase_storage/firebase_storage.dart'; 
import 'package:campuspulse/modules/booking/my_bookings_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final User? user = FirebaseAuth.instance.currentUser;
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final _studentIdController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _phoneController = TextEditingController();
  
  bool _isLoading = false;
  bool _isEditing = false;
  String? _photoUrl;

  @override
  void initState() {
    super.initState();
    _fetchUserData();
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
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error loading profile: $e")));
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
      });
      
      setState(() => _isEditing = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Profile updated successfully!")));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Update failed: $e")));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showChangePasswordDialog() {
    final oldPassController = TextEditingController();
    final newPassController = TextEditingController();
    final confirmNewPassController = TextEditingController(); 
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Change Password"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: oldPassController,
                obscureText: true,
                decoration: const InputDecoration(labelText: "Old Password"),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: newPassController,
                obscureText: true,
                decoration: const InputDecoration(labelText: "New Password"),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: confirmNewPassController,
                obscureText: true,
                decoration: const InputDecoration(labelText: "Confirm New Password"),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              if (newPassController.text != confirmNewPassController.text) {
                 ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("New passwords do not match.")));
                 return;
              }

              final passRegex = RegExp(r'^(?=.*?[A-Z])(?=.*?[a-z])(?=.*?[0-9])(?=.*?[!@#\$&*~]).{8,}$');
              if (!passRegex.hasMatch(newPassController.text)) {
                 ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                   content: Text("Password must be 8+ chars, with Upper, Lower, Number & Special char."),
                   duration: Duration(seconds: 4),
                 ));
                 return;
              }

              Navigator.pop(context); 
              _performPasswordChange(oldPassController.text, newPassController.text);
            },
            child: const Text("Update"),
          ),
        ],
      ),
    );
  }

  Future<void> _performPasswordChange(String oldPass, String newPass) async {
    setState(() => _isLoading = true);
    try {
      AuthCredential credential = EmailAuthProvider.credential(email: user!.email!, password: oldPass);
      await user!.reauthenticateWithCredential(credential);
      await user!.updatePassword(newPass);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Password changed successfully!")));
    } on FirebaseAuthException catch (e) {
      String errorMessage = "Failed to change password.";
      if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        errorMessage = "The old password you entered is incorrect.";
      } else if (e.code == 'weak-password') {
        errorMessage = "The new password is too weak.";
      } else {
        errorMessage = "Error: ${e.message}";
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMessage)));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showDeleteAccountDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Account"),
        content: const Text("Are you sure you want to delete your account? This action cannot be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to delete. Try re-login. Error: $e")));
      setState(() => _isLoading = false);
    }
  }

  Future<void> _editProfilePicture() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 50);
      
      if (image == null) return; 

      setState(() => _isLoading = true);

      final storageRef = FirebaseStorage.instance
          .ref()
          .child('profile_images')
          .child('${user!.uid}.jpg');

      final metadata = SettableMetadata(contentType: 'image/jpeg');
      final TaskSnapshot snapshot = await storageRef.putFile(File(image.path), metadata);
      final downloadUrl = await snapshot.ref.getDownloadURL();

      await FirebaseFirestore.instance.collection('Students').doc(user!.uid).update({
        'photo_url': downloadUrl,
      });

      setState(() {
        _photoUrl = downloadUrl;
        _isLoading = false;
      });

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Profile picture updated!")));

    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to upload image: $e")));
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
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error removing photo: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return Scaffold(
      appBar: AppBar(
        title: const Text("My Profile"),
        automaticallyImplyLeading: false, 
        actions: [
          IconButton(
            icon: Icon(_isEditing ? Icons.check : Icons.edit),
            onPressed: () {
              if (_isEditing) {
                _updateProfile();
              } else {
                setState(() => _isEditing = true);
              }
            },
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // --- Profile Picture Section ---
              Stack(
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: Colors.grey.shade200,
                    backgroundImage: _photoUrl != null && _photoUrl!.isNotEmpty ? NetworkImage(_photoUrl!) : null,
                    onBackgroundImageError: (exception, stackTrace) {
                      debugPrint("Profile image load error: $exception");
                    },
                    child: _photoUrl == null || _photoUrl!.isEmpty 
                      ? const Icon(Icons.person, size: 50, color: Colors.grey) 
                      : null,
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: CircleAvatar(
                      backgroundColor: const Color(0xFF104C97),
                      radius: 18,
                      child: IconButton(
                        icon: const Icon(Icons.camera_alt, size: 18, color: Colors.white),
                        onPressed: _editProfilePicture,
                      ),
                    ),
                  )
                ],
              ),
              if (_photoUrl != null && _photoUrl!.isNotEmpty)
                TextButton(onPressed: _removeProfilePicture, child: const Text("Remove Photo", style: TextStyle(color: Colors.red))),

              const SizedBox(height: 30),

              // --- My Bookings Button ---
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const MyBookingsPage()));
                  },
                  icon: const Icon(Icons.history_edu),
                  label: const Text("My Bookings"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF104C97),
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 20),

              // --- Editable Fields ---
              _buildTextField("Student ID", _studentIdController, enabled: _isEditing, isNumeric: true,
                validator: (val) => RegExp(r'^[0-9]{11}$').hasMatch(val!) ? null : "ID must be 11 digits"),
              
              _buildTextField("Full Name", _fullNameController, enabled: _isEditing,
                validator: (val) => val!.isEmpty ? "Cannot be empty" : null),

              _buildTextField("Username (Optional)", _usernameController, enabled: _isEditing, hint: "Display name for greeting"),
              
              _buildTextField("Phone Number", _phoneController, enabled: _isEditing, isNumeric: true,
                validator: (val) => RegExp(r'^(\+?60|0)[0-9]{1,2}-?[0-9]{7,8}$').hasMatch(val!) ? null : "Invalid Malaysia format"),

              const SizedBox(height: 10),
              
              // --- Non-Editable Fields ---
              TextFormField(
                initialValue: user?.email,
                enabled: false,
                decoration: const InputDecoration(labelText: "Email (Cannot be changed)", prefixIcon: Icon(Icons.email)),
              ),

              const SizedBox(height: 30),

              // --- Action Buttons ---
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _showChangePasswordDialog,
                  child: const Text("Change Password"),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                  onPressed: _showDeleteAccountDialog,
                  child: const Text("Delete Account"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, {
    bool enabled = true, 
    bool isNumeric = false, 
    String? Function(String?)? validator,
    String? hint
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: TextFormField(
        controller: controller,
        enabled: enabled,
        keyboardType: isNumeric ? TextInputType.number : TextInputType.text,
        validator: validator,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          filled: !enabled,
          fillColor: enabled ? Colors.transparent : Colors.grey.shade100,
        ),
      ),
    );
  }
}