import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class InfographicPage extends StatefulWidget {
  const InfographicPage({super.key});

  @override
  State<InfographicPage> createState() => _InfographicPageState();
}

class _InfographicPageState extends State<InfographicPage> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFF8F9FA))
      // --- THE FIX: Establish a bridge between JavaScript and Flutter ---
      ..addJavaScriptChannel(
        'CampusPulse',
        onMessageReceived: (JavaScriptMessage message) {
          // Listen for the 'close' message sent from the HTML button
          if (message.message == 'close') {
            if (mounted) {
              Navigator.pop(context); // Exits the Infographic Page
            }
          }
        },
      )
      ..loadFlutterAsset('assets/web/index.html');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF262562)),
        title: const Text("User Guide", style: TextStyle(color: Color(0xFF262562), fontWeight: FontWeight.w800)),
        centerTitle: true,
      ),
      body: SafeArea(
        child: WebViewWidget(controller: _controller),
      ),
    );
  }
}