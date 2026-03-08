import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  // Controllers
  final studentIdController = TextEditingController(); 
  final fullNameController = TextEditingController();
  final emailController = TextEditingController();
  final phoneController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  bool isLoading = false;
  
  // Visibility States
  bool _isPasswordObscure = true;
  bool _isConfirmPasswordObscure = true;

  // --- NEW: Pop-up Error Dialog ---
  void _showErrorDialog(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 10),
            Text("Registration Issue"),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("OK", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // --- NEW: Friendly Error Mapper ---
  String _mapRegisterError(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return "An account already exists with this email address.";
      case 'weak-password':
        return "The password is too weak. Please use at least 6 characters.";
      case 'invalid-email':
        return "The email address is not formatted correctly.";
      case 'network-request-failed':
        return "Network error. Please check your internet connection.";
      default:
        return "Registration failed. ${e.message}";
    }
  }

  Future<void> registerUser() async {
    final studentId = studentIdController.text.trim();
    final fullName = fullNameController.text.trim();
    final email = emailController.text.trim();
    final phone = phoneController.text.trim();
    final pass = passwordController.text.trim();
    final confirmPass = confirmPasswordController.text.trim();

    if (studentId.isEmpty || fullName.isEmpty || email.isEmpty || phone.isEmpty || pass.isEmpty || confirmPass.isEmpty) {
      _showErrorDialog("Please fill in all fields.");
      return;
    }

    final studentIdRegex = RegExp(r'^[0-9]{11}$');
    if (!studentIdRegex.hasMatch(studentId)) {
      _showErrorDialog("Student ID must be exactly 11 digits (numbers only).");
      return;
    }

    final phoneRegex = RegExp(r'^(\+?60|0)[0-9]{1,2}-?[0-9]{7,8}$');
    if (!phoneRegex.hasMatch(phone)) {
      _showErrorDialog("Please enter a valid phone number (e.g., 0123456789).");
      return;
    }

    if (!email.endsWith("@s.unikl.edu.my")) {
      _showErrorDialog("Only UniKL student emails (@s.unikl.edu.my) are allowed.");
      return;
    }

    final passwordRegex = RegExp(r'^(?=.*?[A-Z])(?=.*?[a-z])(?=.*?[0-9])(?=.*?[!@#\$&*~]).{8,}$');
    if (!passwordRegex.hasMatch(pass)) {
      _showErrorDialog("Password must be at least 8 characters and include uppercase, lowercase, number, and special characters.");
      return;
    }

    if (pass != confirmPass) {
      _showErrorDialog("Passwords do not match.");
      return;
    }

    try {
      setState(() => isLoading = true);

      UserCredential userCred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: pass,
      );

      await userCred.user!.sendEmailVerification();

      await FirebaseFirestore.instance.collection("Students").doc(userCred.user!.uid).set({
        "uid": userCred.user!.uid,
        "student_id": studentId,
        "full_name": fullName,
        "username": "",
        "student_email": email,
        "phone_number": phone,
        "photo_url": "",
        "registration_date": FieldValue.serverTimestamp(),
        "status": "pending_verification",
        "has_completed_profile": false,
      });

      if (!mounted) return;
      setState(() => isLoading = false);
      
      Navigator.pushReplacementNamed(context, '/verify_email');

    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => isLoading = false);
      _showErrorDialog(_mapRegisterError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Student Registration")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
             const Text("Create your account to start booking shuttles."),
             const SizedBox(height: 20),
            
            _buildTextField("Student ID", studentIdController, type: TextInputType.number, hint: "11-digit Student ID"),
            _buildTextField("Full Name", fullNameController, hint: "e.g. Muhammad Ali"),
            _buildTextField("Student Email", emailController, type: TextInputType.emailAddress, hint: "example@s.unikl.edu.my"),
            _buildTextField("Phone Number", phoneController, type: TextInputType.phone, hint: "e.g. 0123456789"),
            
            _buildPasswordField("Password", passwordController, _isPasswordObscure, (val) {
              setState(() => _isPasswordObscure = val);
            }),

            _buildPasswordField("Confirm Password", confirmPasswordController, _isConfirmPasswordObscure, (val) {
              setState(() => _isConfirmPasswordObscure = val);
            }),
            
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: isLoading ? null : registerUser,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF104C97),
                  foregroundColor: Colors.white,
                ),
                child: isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text("Register"),
              ),
            ),
            const SizedBox(height: 16),
             Center(
               child: TextButton(
                  onPressed: () => Navigator.pushNamed(context, '/login'),
                  child: const Text("Already have an account? Login"),
                ),
             ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, {TextInputType? type, String? hint}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: TextField(
        controller: controller,
        keyboardType: type,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
        ),
      ),
    );
  }

  Widget _buildPasswordField(String label, TextEditingController controller, bool isObscure, Function(bool) onToggle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: TextField(
        controller: controller,
        obscureText: isObscure,
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: IconButton(
            icon: Icon(
              isObscure ? Icons.visibility_off : Icons.visibility,
              color: Colors.grey,
            ),
            onPressed: () => onToggle(!isObscure),
          ),
        ),
      ),
    );
  }
}