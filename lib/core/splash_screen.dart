import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:campuspulse/data/services/notification_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    
    _controller = AnimationController(
      duration: const Duration(seconds: 5),
      vsync: this,
    )..forward();
    
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeIn,
    );

    _checkAuthAndNavigate();
  }

  // --- NEW: Smart Auth-Aware Navigation ---
  Future<void> _checkAuthAndNavigate() async {
    // Wait for the animation and branding to show
    await Future.delayed(const Duration(seconds: 5));

    if (!mounted) return;

    final user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      // User is logged in
      if (user.emailVerified) {
        debugPrint("!!! [AUTH] User verified. Syncing FCM token...");
        
        // --- IMPROVED: Safe Sync Wrapper ---
        // We run this in a try-catch to prevent DEVELOPER_ERROR from potentially 
        // blocking the navigation logic in some edge cases.
        try {
          NotificationService().saveTokenToDatabase();
        } catch (e) {
          debugPrint("!!! [AUTH] Non-fatal notification sync error: $e");
        }

        Navigator.pushReplacementNamed(context, '/home');
      } else {
        // User created account but didn't verify yet
        Navigator.pushReplacementNamed(context, '/verify_email');
      }
    } else {
      // No session, go to landing/onboarding
      Navigator.pushReplacementNamed(context, '/landing');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: FadeTransition(
          opacity: _animation,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // --- REVISED: Custom Logo Integration with Fallback ---
              Image.asset(
                'assets/images/campuspulse_logo.png', // Ensure this file exists in your assets!
                width: 300, // Adjust width based on your logo's aspect ratio
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  // SAFE FALLBACK: If the image is missing, it shows the old UI instead of crashing
                  return Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFF262562).withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.directions_bus_filled, 
                          size: 80, 
                          color: Color(0xFF262562),
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        "CampusPulse",
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF262562),
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        "Smart Shuttle for UniKL",
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  );
                },
              ),
              
              const SizedBox(height: 48),
              
              const CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFFF0AB00),
              )
            ],
          ),
        ),
      ),
    );
  }
}