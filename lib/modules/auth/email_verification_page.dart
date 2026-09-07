import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class EmailVerificationPage extends StatefulWidget {
  const EmailVerificationPage({super.key});

  @override
  State<EmailVerificationPage> createState() => _EmailVerificationPageState();
}

class _EmailVerificationPageState extends State<EmailVerificationPage> {
  bool isEmailVerified = false;
  Timer? timer;
  bool canResendEmail = false;
  bool verificationDetected = false; 

  @override
  void initState() {
    super.initState();
    
    isEmailVerified = FirebaseAuth.instance.currentUser?.emailVerified ?? false;

    if (!isEmailVerified) {
      // Keep checking every 3 seconds to see if the user clicked the link
      timer = Timer.periodic(
        const Duration(seconds: 3),
        (_) => checkEmailVerified(),
      );
      
      // Automatically send the first verification email upon page load
      sendVerificationEmail();
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> checkEmailVerified() async {
    // Reload user to get latest status from Firebase
    await FirebaseAuth.instance.currentUser?.reload();
    final verified = FirebaseAuth.instance.currentUser?.emailVerified ?? false;

    if (verified) {
      timer?.cancel();
      
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance.collection("Students").doc(user.uid).update({
          "status": "active"
        });
      }

      if (mounted) {
        setState(() {
          isEmailVerified = true;
          verificationDetected = true;
        });
      }
    }
  }

  Future<void> sendVerificationEmail() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      await user?.sendEmailVerification();
      
      setState(() {
        canResendEmail = false;
      });
      
      showMessage("Verification email sent! Please check your inbox.");
      
      // Prevent spamming the resend button
      await Future.delayed(const Duration(seconds: 30));
      if (mounted) setState(() => canResendEmail = true);
      
    } catch (e) {
      showMessage("Error: ${e.toString()}");
    }
  }
  
  void showMessage(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF104C97),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.all(20),
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    // --- 1. SUCCESS UI ---
    if (verificationDetected) {
       return Scaffold(
         backgroundColor: Colors.white,
         body: Padding(
           padding: const EdgeInsets.all(24.0),
           child: Center(
             child: Column(
               mainAxisAlignment: MainAxisAlignment.center,
               children: [
                 Container(
                   padding: const EdgeInsets.all(24),
                   decoration: BoxDecoration(color: Colors.green.shade50, shape: BoxShape.circle),
                   child: const Icon(Icons.verified_user_rounded, size: 80, color: Colors.green),
                 ),
                 const SizedBox(height: 32),
                 const Text(
                   "Identity Verified!",
                   style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Color(0xFF104C97), letterSpacing: -0.5),
                 ),
                 const SizedBox(height: 12),
                 Text(
                   "Your UniKL student email has been successfully authenticated.",
                   textAlign: TextAlign.center,
                   style: TextStyle(color: Colors.grey.shade600, fontSize: 16, height: 1.4),
                 ),
                 const SizedBox(height: 48),
                 SizedBox(
                   width: double.infinity,
                   height: 60,
                   child: ElevatedButton(
                     onPressed: () {
                       Navigator.of(context).pushReplacementNamed('/home');
                     },
                     style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF104C97),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        elevation: 5,
                        shadowColor: const Color(0xFF104C97).withOpacity(0.4),
                     ),
                     child: const Text("Access CampusPulse", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, letterSpacing: 0.5)),
                   ),
                 ),
               ],
             ),
           ),
         ),
       );
    }

    // --- 2. WAITING FOR MANUAL VERIFICATION UI ---
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF104C97)),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: Colors.orange.shade50, shape: BoxShape.circle),
              child: const Icon(Icons.mark_email_unread_rounded, size: 60, color: Colors.orange),
            ),
            const SizedBox(height: 32),
            const Text(
              "Check Your Email",
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Color(0xFF104C97), letterSpacing: -0.5),
            ),
            const SizedBox(height: 12),
            Text(
              "We've sent a verification link to:\n${FirebaseAuth.instance.currentUser?.email}",
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black87, fontSize: 15, height: 1.5, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            Text(
              "Please open your Outlook inbox and click the link to verify your account. This page will automatically update once verified.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 40),
            
            const CircularProgressIndicator(color: Color(0xFF104C97)),
            const SizedBox(height: 16),
            const Text("Waiting for verification...", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)),
            
            const SizedBox(height: 40),
            
            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton.icon(
                onPressed: canResendEmail ? sendVerificationEmail : null,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text("Resend Email", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF104C97),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade300,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              "Check your Junk/Spam folder if you don't see the email.",
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500, fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 40),
            
            TextButton(
              onPressed: () {
                FirebaseAuth.instance.signOut();
                Navigator.pushReplacementNamed(context, '/login');
              }, 
              child: const Text("Cancel & Back to Login", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 16)),
            )
          ],
        ),
      ),
    );
  }
}