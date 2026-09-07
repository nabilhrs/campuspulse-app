import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:campuspulse/data/services/notification_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  
  bool isLoading = false;
  bool _isPasswordObscure = true; 

  // --- MODERNIZED ERROR DIALOG ---
  void _showErrorDialog(String title, String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), shape: BoxShape.circle),
              child: const Icon(Icons.error_outline, color: Colors.red, size: 24),
            ),
            const SizedBox(width: 12),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
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

  String _mapLoginError(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return "Incorrect email or password. Please try again.";
      case 'invalid-email':
        return "The email address entered is invalid.";
      case 'user-disabled':
        return "This account has been disabled. Please contact support.";
      case 'too-many-requests':
        return "Too many failed attempts. Please try again later.";
      case 'network-request-failed':
        return "Network error. Please check your internet connection.";
      default:
        return "An unknown error occurred. (${e.message})";
    }
  }

  // --- MODERNIZED FORGOT PASSWORD DIALOG ---
  void showForgotPasswordDialog() {
    final resetEmailController = TextEditingController();
    resetEmailController.text = emailController.text;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text("Reset Password", style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF262562))),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Enter your student email. We will send you a secure link to reset your password.", style: TextStyle(color: Colors.grey, height: 1.4)),
            const SizedBox(height: 20),
            _buildModernTextField(
              controller: resetEmailController,
              label: "Student Email",
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        actions: [
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () async {
                    final email = resetEmailController.text.trim();
                    if (email.isEmpty) {
                      _showErrorDialog("Required", "Please enter your email.");
                      return;
                    }
                    Navigator.pop(context); 
                    try {
                      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text("Reset link sent! Please check your inbox.", style: TextStyle(fontWeight: FontWeight.bold)),
                            backgroundColor: Colors.green,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            margin: const EdgeInsets.all(20),
                          ),
                        );
                      }
                    } on FirebaseAuthException catch (e) {
                      _showErrorDialog("Reset Failed", e.message ?? "Could not send reset email.");
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF262562),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12)
                  ),
                  child: const Text("Send Link", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> login() async {
    if (emailController.text.isEmpty || passwordController.text.isEmpty) {
      _showErrorDialog("Incomplete Input", "Please enter both email and password.");
      return;
    }

    try {
      setState(() => isLoading = true);

      final userCred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      if (!userCred.user!.emailVerified) {
        setState(() => isLoading = false);
        Navigator.pushNamed(context, '/verify_email');
        return;
      }

      await NotificationService().saveTokenToDatabase();

      if (!mounted) return;
      setState(() => isLoading = false);
      Navigator.pushReplacementNamed(context, '/home'); 

    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => isLoading = false);
      _showErrorDialog("Login Failed", _mapLoginError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 40.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // --- HEADER BRANDING ---
                const SizedBox(height: 30),
                Center(
                  child: Image.asset(
                    'assets/images/campuspulse_logo.png', 
                    height: 80, 
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFF262562).withOpacity(0.05),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.directions_bus_rounded, size: 70, color: Color(0xFF262562)),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 32),
                const Text(
                  "Welcome Back",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: Color(0xFF262562), letterSpacing: -0.5),
                ),
                const SizedBox(height: 8),
                Text(
                  "Sign in to continue booking your shuttles.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 48),
                
                // --- INPUT FIELDS ---
                _buildModernTextField(
                  controller: emailController,
                  label: "Student Email",
                  icon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 20),
                _buildModernTextField(
                  controller: passwordController,
                  label: "Password",
                  icon: Icons.lock_outline,
                  isObscure: _isPasswordObscure,
                  onToggleObscure: () => setState(() => _isPasswordObscure = !_isPasswordObscure),
                ),
                
                // --- FORGOT PASSWORD ---
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: showForgotPasswordDialog,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      "Forgot Password?",
                      style: TextStyle(color: Color(0xFF262562), fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                ),

                const SizedBox(height: 32),
                
                // --- LOGIN BUTTON ---
                SizedBox(
                  height: 60,
                  child: ElevatedButton(
                    onPressed: isLoading ? null : login,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF262562),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      elevation: 5,
                      shadowColor: const Color(0xFF262562).withOpacity(0.4),
                    ),
                    child: isLoading
                        ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                        : const Text("Login", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                  ),
                ),
                
                const SizedBox(height: 32),
                
                // --- REGISTER LINK ---
                Center(
                  child: GestureDetector(
                    onTap: () => Navigator.pushNamed(context, '/register'),
                    child: RichText(
                      text: TextSpan(
                        text: "Don't have an account? ",
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 14, fontWeight: FontWeight.w500),
                        children: const [
                          TextSpan(
                            text: "Register here",
                            style: TextStyle(color: Color(0xFF262562), fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
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
    TextInputType? keyboardType,
    bool isObscure = false,
    VoidCallback? onToggleObscure,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: isObscure,
      keyboardType: keyboardType,
      style: const TextStyle(fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        labelText: label,
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