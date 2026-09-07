import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class PoliciesPage extends StatefulWidget {
  const PoliciesPage({super.key});

  @override
  State<PoliciesPage> createState() => _PoliciesPageState();
}

class _PoliciesPageState extends State<PoliciesPage> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFF8F9FA))
      // Establish a bridge between JavaScript and Flutter
      ..addJavaScriptChannel(
        'CampusPulse',
        onMessageReceived: (JavaScriptMessage message) {
          // Listen for the 'close' message sent from the HTML Accept button
          if (message.message == 'close') {
            if (mounted) {
              Navigator.pop(context); // Exits the Policies Page
            }
          }
        },
      )
      ..loadFlutterAsset('assets/web/rules_regulations.html');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF262562)),
        title: const Text("Terms & Policies", style: TextStyle(color: Color(0xFF262562), fontWeight: FontWeight.w800)),
        centerTitle: true,
      ),
      body: SafeArea(
        child: WebViewWidget(controller: _controller),
      ),
    );
  }
}