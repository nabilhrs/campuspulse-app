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
  bool verificationDetected = false; // New state to control UI

  @override
  void initState() {
    super.initState();
    
    // Check if already verified
    isEmailVerified = FirebaseAuth.instance.currentUser?.emailVerified ?? false;

    if (!isEmailVerified) {
      // Periodically check if the user (or their email server) clicked the link
      timer = Timer.periodic(
        const Duration(seconds: 3),
        (_) => checkEmailVerified(),
      );
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
      
      // Update Firestore status to 'active'
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance.collection("Students").doc(user.uid).update({
          "status": "active"
        });
      }

      // Update state to show the "Continue" button instead of auto-redirecting
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
      setState(() => canResendEmail = false);
      await Future.delayed(const Duration(seconds: 5));
      setState(() => canResendEmail = true);
    } catch (e) {
      showMessage(e.toString());
    }
  }
  
  void showMessage(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    // If verification is detected, show the "Success" UI
    if (verificationDetected) {
       return Scaffold(
         body: Padding(
           padding: const EdgeInsets.all(24.0),
           child: Center(
             child: Column(
               mainAxisAlignment: MainAxisAlignment.center,
               children: [
                 const Icon(Icons.check_circle_outline, size: 100, color: Colors.green),
                 const SizedBox(height: 24),
                 const Text(
                   "Verified Successfully!",
                   style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF104C97)),
                 ),
                 const SizedBox(height: 12),
                 const Text(
                   "Your email has been confirmed. You may now access the app.",
                   textAlign: TextAlign.center,
                   style: TextStyle(color: Colors.grey, fontSize: 16),
                 ),
                 const SizedBox(height: 40),
                 SizedBox(
                   width: double.infinity,
                   height: 50,
                   child: ElevatedButton(
                     onPressed: () {
                       Navigator.of(context).pushReplacementNamed('/home');
                     },
                     style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF104C97),
                        foregroundColor: Colors.white,
                     ),
                     child: const Text("Continue to CampusPulse"),
                   ),
                 ),
               ],
             ),
           ),
         ),
       );
    }

    // Default "Waiting" UI
    return Scaffold(
      appBar: AppBar(title: const Text("Verify Email")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.mark_email_unread, size: 80, color: Color(0xFF104C97)),
            const SizedBox(height: 20),
            const Text(
              "Verification Email Sent",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              "We have sent a verification link to:\n${FirebaseAuth.instance.currentUser?.email}",
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 20),
            const Text(
              "Please check your Outlook/Inbox and click the link to verify your account.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 20),
            const CircularProgressIndicator(),
            const SizedBox(height: 10),
            const Text("Waiting for verification..."),
            const SizedBox(height: 40),
            
            ElevatedButton.icon(
              onPressed: canResendEmail ? sendVerificationEmail : null,
              icon: const Icon(Icons.email),
              label: const Text("Resend Email"),
            ),
            
            // Added Spam/Junk hint text here
            const Padding(
              padding: EdgeInsets.only(top: 8.0),
              child: Text(
                "Check your Junk/Spam folder if you don't see the email.",
                style: TextStyle(fontSize: 12, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ),

            const SizedBox(height: 10),
            
            TextButton(
              onPressed: () {
                FirebaseAuth.instance.signOut();
                Navigator.pushReplacementNamed(context, '/login');
              }, 
              child: const Text("Cancel"),
            )
          ],
        ),
      ),
    );
  }
}