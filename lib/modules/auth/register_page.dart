import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:campuspulse/data/services/notification_service.dart';
import 'package:campuspulse/modules/home/policies_page.dart'; // --- NEW: Import Policies Page ---

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final studentIdController = TextEditingController(); 
  final fullNameController = TextEditingController();
  final emailController = TextEditingController();
  final phoneController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  bool isLoading = false;
  bool _isPasswordObscure = true;
  bool _isConfirmPasswordObscure = true;
  
  bool _hasAcceptedTerms = false;
  late TapGestureRecognizer _termsRecognizer; // --- NEW: Gesture Recognizer for RichText ---

  @override
  void initState() {
    super.initState();
    _termsRecognizer = TapGestureRecognizer()
      ..onTap = () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const PoliciesPage()));
      };
  }

  @override
  void dispose() {
    _termsRecognizer.dispose();
    studentIdController.dispose();
    fullNameController.dispose();
    emailController.dispose();
    phoneController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  void _showErrorDialog(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), shape: BoxShape.circle),
              child: const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 24),
            ),
            const SizedBox(width: 12),
            const Text("Registration Issue", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          ],
        ),
        content: Text(message, style: TextStyle(color: Colors.grey.shade700, height: 1.4)),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF262562),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 12)
              ),
              child: const Text("Got it", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }

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

    if (!studentId.contains(RegExp(r'^[0-9]{11}$'))) {
      _showErrorDialog("Student ID must be exactly 11 digits.");
      return;
    }

    if (!email.endsWith("@s.unikl.edu.my")) {
      _showErrorDialog("Only UniKL student emails are allowed.");
      return;
    }

    if (pass != confirmPass) {
      _showErrorDialog("Passwords do not match.");
      return;
    }
    
    if (!_hasAcceptedTerms) {
      _showErrorDialog("You must accept the CampusPulse Terms of Use & Service Policy to register.");
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

      await NotificationService().saveTokenToDatabase();

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
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF262562)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 10.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- HEADER ---
              const Text(
                "Create Account",
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Color(0xFF262562), letterSpacing: -0.5),
              ),
              const SizedBox(height: 8),
              Text(
                "Sign up using your UniKL student credentials to start booking shuttles.",
                style: TextStyle(fontSize: 15, color: Colors.grey.shade600, fontWeight: FontWeight.w500, height: 1.4),
              ),
              const SizedBox(height: 36),
              
              // --- FORM FIELDS ---
              _buildModernTextField(
                controller: studentIdController,
                label: "Student ID",
                hint: "e.g. 52213123456",
                icon: Icons.badge_outlined,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              
              _buildModernTextField(
                controller: fullNameController,
                label: "Full Name",
                hint: "e.g. Muhammad Ali",
                icon: Icons.person_outline,
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 16),
              
              _buildModernTextField(
                controller: emailController,
                label: "Student Email",
                hint: "example@s.unikl.edu.my",
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),
              
              _buildModernTextField(
                controller: phoneController,
                label: "Phone Number",
                hint: "e.g. 0123456789",
                icon: Icons.phone_outlined,
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),
              
              _buildModernTextField(
                controller: passwordController,
                label: "Password",
                hint: "Minimum 6 characters",
                icon: Icons.lock_outline,
                isObscure: _isPasswordObscure,
                onToggleObscure: () => setState(() => _isPasswordObscure = !_isPasswordObscure),
              ),
              const SizedBox(height: 16),

              _buildModernTextField(
                controller: confirmPasswordController,
                label: "Confirm Password",
                hint: "Re-enter your password",
                icon: Icons.lock_reset_outlined,
                isObscure: _isConfirmPasswordObscure,
                onToggleObscure: () => setState(() => _isConfirmPasswordObscure = !_isConfirmPasswordObscure),
              ),
              
              const SizedBox(height: 24),
              
              // --- THE FIX: Clickable Terms of Use Checkbox ---
              Container(
                decoration: BoxDecoration(
                  color: _hasAcceptedTerms ? Colors.green.shade50 : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _hasAcceptedTerms ? Colors.green.shade200 : Colors.grey.shade300),
                ),
                child: CheckboxListTile(
                  value: _hasAcceptedTerms,
                  activeColor: Colors.green,
                  checkColor: Colors.white,
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  onChanged: (val) {
                    setState(() {
                      _hasAcceptedTerms = val ?? false;
                    });
                  },
                  title: RichText(
                    text: TextSpan(
                      text: "I have read and agree to the CampusPulse ",
                      style: TextStyle(
                        fontSize: 13, 
                        color: Colors.grey.shade800, 
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Inter', // Maintain font consistency
                      ),
                      children: [
                        TextSpan(
                          text: "Terms of Use & Service Policy.",
                          style: const TextStyle(
                            color: Color(0xFF262562), 
                            decoration: TextDecoration.underline,
                            fontWeight: FontWeight.bold
                          ),
                          recognizer: _termsRecognizer,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              
              const SizedBox(height: 32),
              
              // --- REGISTER BUTTON ---
              SizedBox(
                width: double.infinity,
                height: 60,
                child: ElevatedButton(
                  onPressed: isLoading ? null : registerUser,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF262562),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    elevation: 5,
                    shadowColor: const Color(0xFF262562).withOpacity(0.4),
                  ),
                  child: isLoading
                      ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                      : const Text("Register Now", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                ),
              ),
              
              const SizedBox(height: 32),
              
              // --- LOGIN LINK ---
              Center(
                child: GestureDetector(
                  onTap: () => Navigator.pushReplacementNamed(context, '/login'),
                  child: RichText(
                    text: TextSpan(
                      text: "Already have an account? ",
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 14, fontWeight: FontWeight.w500),
                      children: const [
                        TextSpan(
                          text: "Login here",
                          style: TextStyle(color: Color(0xFF262562), fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  // --- HELPER: Modern TextField ---
  Widget _buildModernTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
    bool isObscure = false,
    VoidCallback? onToggleObscure,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: isObscure,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      style: const TextStyle(fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey.shade400, fontWeight: FontWeight.normal),
        labelStyle: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.w500),
        prefixIcon: Icon(icon, color: Colors.grey.shade400, size: 22),
        suffixIcon: onToggleObscure != null
            ? IconButton(
                icon: Icon(isObscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: Colors.grey.shade400, size: 20),
                onPressed: onToggleObscure,
              )
            : null,
        filled: true,
        fillColor: Colors.grey.shade50,
        contentPadding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: Colors.grey.shade200, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: Colors.grey.shade200, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: Color(0xFF262562), width: 2),
        ),
      ),
    );
  }
}