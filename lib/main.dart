import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:campuspulse/modules/auth/login_page.dart';
import 'package:campuspulse/modules/auth/register_page.dart';
import 'package:campuspulse/modules/auth/email_verification_page.dart';
import 'package:campuspulse/modules/home/home_page.dart';
import 'package:campuspulse/core/splash_screen.dart'; 
import 'package:campuspulse/data/services/notification_service.dart';
import 'package:campuspulse/modules/home/infographic_page.dart'; // --- NEW: Import for User Guide ---
import 'firebase_options.dart'; 
import 'package:firebase_messaging/firebase_messaging.dart';

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint("Handling a background message: ${message.messageId}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");  
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  NotificationService().initNotification();
  
  runApp(const CampusPulse());
}

class CampusPulse extends StatelessWidget {
  const CampusPulse({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CampusPulse',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        // UniKL Colors
        primaryColor: const Color(0xFF262562), // UniKL Blue
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF262562),
          secondary: const Color(0xFFF0AB00), // UniKL Yellow/Orange
        ),
        useMaterial3: true,
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          filled: true,
          fillColor: Colors.grey.shade50,
        ),
      ),

      initialRoute: '/splash', 
      routes: {
        '/splash': (context) => const SplashScreen(), 
        '/landing': (context) => const LandingPage(),
        '/login': (context) => const LoginPage(),
        '/register': (context) => const RegisterPage(),
        '/verify_email': (context) => const EmailVerificationPage(),
        '/home': (context) => const HomePage(),
      },
    );
  }
}

class LandingPage extends StatelessWidget {
  const LandingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // --- UPDATED: Integrated Custom Logo with Fallback ---
            Image.asset(
              'assets/images/campuspulse_logo.png', // Ensure this file exists in your assets!
              height: 85, // Slightly larger for the main landing page
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                // SAFE FALLBACK: If the image is missing, it shows the old UI instead of crashing
                return Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF262562).withOpacity(0.05),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.directions_bus_filled, size: 80, color: Color(0xFF262562)),
                );
              },
            ),
            const SizedBox(height: 24),
            const Text(
              "Smart Shuttle for UniKL Students",
              style: TextStyle(fontSize: 16, color: Colors.grey, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 30),
            
            // --- POLISHED BUTTONS ---
            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton(
                onPressed: () => Navigator.pushNamed(context, '/login'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF262562),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  elevation: 5,
                  shadowColor: const Color(0xFF262562).withOpacity(0.4),
                ),
                child: const Text("Login", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 60,
              child: OutlinedButton(
                onPressed: () => Navigator.pushNamed(context, '/register'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF262562),
                  side: const BorderSide(color: Color(0xFF262562), width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                child: const Text("Create Account", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
              ),
            ),
            const SizedBox(height: 16),
            
            // --- NEW: User Guide Link ---
            TextButton.icon(
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const InfographicPage()));
              },
              icon: const Icon(Icons.menu_book_rounded, color: Colors.grey),
              label: const Text("How CampusPulse Works", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, decoration: TextDecoration.underline)),
            ),
          ],
        ),
      ),
    );
  }
}