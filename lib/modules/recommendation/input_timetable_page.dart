// import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// ARCHIVED: Smart Scan Imports
// import 'package:image_picker/image_picker.dart';
// import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class InputTimetablePage extends StatefulWidget {
  const InputTimetablePage({super.key});

  @override
  State<InputTimetablePage> createState() => _InputTimetablePageState();
}

class _InputTimetablePageState extends State<InputTimetablePage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final User? user = FirebaseAuth.instance.currentUser;
  bool _isLoading = false;
  // bool _isScanning = false; // ARCHIVED: Smart Scan State

  final List<String> days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

  // UniKL Time Slots
  final List<String> timeSlots = [
    "08:30 - 09:30",
    "09:30 - 10:30",
    "10:30 - 11:30",
    "11:30 - 12:30",
    "12:30 - 13:30",
    "13:30 - 14:30",
    "14:30 - 15:30",
    "15:30 - 16:30",
    "16:30 - 17:30",
    "17:30 - 18:30",
    "18:30 - 19:30",
    "19:30 - 20:30",
    "20:30 - 21:30",
  ];

  Map<String, List<String>> selectedSlots = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: days.length, vsync: this);
    for (var day in days) {
      selectedSlots[day] = [];
    }
    _fetchExistingTimetable();
  }

  Future<void> _fetchExistingTimetable() async {
    if (user == null) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('Students').doc(user!.uid).get();
      if (doc.exists && doc.data()!.containsKey('timetable')) {
        setState(() {
          Map<String, dynamic> data = doc.data()!['timetable'];
          data.forEach((key, value) {
            if (days.contains(key)) {
              selectedSlots[key] = List<String>.from(value);
            }
          });
        });
      }
    } catch (e) {
      debugPrint("Error loading timetable: $e");
    }
  }

  void _showFloatingSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white))),
          ],
        ),
        backgroundColor: isError ? Colors.redAccent : Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.only(bottom: 30, left: 20, right: 20),
        elevation: 10,
      ),
    );
  }

  Future<void> _saveTimetable() async {
    setState(() => _isLoading = true);
    try {
      await FirebaseFirestore.instance.collection('Students').doc(user!.uid).set({
        'timetable': selectedSlots
      }, SetOptions(merge: true));

      if (mounted) {
        _showFloatingSnackBar("Class schedule saved successfully!");
        Navigator.pop(context); 
      }
    } catch (e) {
      if (mounted) {
        _showFloatingSnackBar("Error saving schedule: $e", isError: true);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _toggleSlot(String day, String slot) {
    setState(() {
      if (selectedSlots[day]!.contains(slot)) {
        selectedSlots[day]!.remove(slot);
      } else {
        selectedSlots[day]!.add(slot);
      }
    });
  }

  /* =================================================================================
     ARCHIVED: SMART SCAN FEATURE (Pending Accuracy Improvements)
     =================================================================================

  void _showScanOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 24),
              const Text("Smart Scan Timetable", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF262562))),
              const SizedBox(height: 8),
              const Text("Upload a photo or screenshot of your class schedule.", style: TextStyle(color: Colors.grey), textAlign: TextAlign.center),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildScanOptionButton(Icons.camera_alt_rounded, "Camera", ImageSource.camera),
                  _buildScanOptionButton(Icons.photo_library_rounded, "Gallery", ImageSource.gallery),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      }
    );
  }

  Widget _buildScanOptionButton(IconData icon, String label, ImageSource source) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
        _processImage(source);
      },
      child: Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFF262562).withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(icon, size: 32, color: const Color(0xFF262562)),
            ),
            const SizedBox(height: 12),
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
          ],
        ),
      ),
    );
  }

  Future<void> _processImage(ImageSource source) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: source);
    if (pickedFile == null) return;

    setState(() => _isScanning = true);

    try {
      final inputImage = InputImage.fromFilePath(pickedFile.path);
      final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
      
      final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
      await textRecognizer.close();

      _parseTimetableSpatial(recognizedText);

    } catch (e) {
      _showFloatingSnackBar("Failed to read image. Please try again.", isError: true);
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  // --- THE PERFECTED SPATIAL OCR BRAIN ---
  void _parseTimetableSpatial(RecognizedText recognizedText) {
    Map<String, double> dayY = {};
    Map<String, List<double>> colXList = {};
    List<Rect> classRects = [];
    List<Rect> onlineRects = []; // NEW: Track online blocks securely
    
    final dayMap = {
      'mon': 'Mon', 'monday': 'Mon',
      'tue': 'Tue', 'tuesday': 'Tue',
      'wed': 'Wed', 'wednesday': 'Wed',
      'thu': 'Thu', 'thursday': 'Thu',
      'fri': 'Fri', 'friday': 'Fri',
      'sat': 'Sat', 'saturday': 'Sat',
      'sun': 'Sun', 'sunday': 'Sun'
    };

    final timeReg = RegExp(r'^((?:0?[0-9]|1[0-9]|2[0-3]))[:.]?30\s*(am|pm|a\.m\.|p\.m\.)?');
    final classReg = RegExp(r'([a-z]{3,4}\s*\d{3,5})|\([lbt]\)|room\s*:|group\s*:');
    // THE FIX: Robust Regex to catch Online even if OCR reads it as 0n1ine
    final onlineReg = RegExp(r'[o0]n[l1]ine');

    for (TextBlock block in recognizedText.blocks) {
      String originalLower = block.text.toLowerCase();
      
      // Track 'online' rects BEFORE any string mutation happens
      if (onlineReg.hasMatch(originalLower)) {
        onlineRects.add(block.boundingBox);
      }

      String blockText = originalLower.replaceAll('o', '0').replaceAll('l', '1');
      
      if (classReg.hasMatch(blockText) && !blockText.contains('day') && !blockText.contains('slot')) {
        classRects.add(block.boundingBox);
      }

      for (TextLine line in block.lines) {
        for (TextElement element in line.elements) {
          // EXTRACT DAYS: Strip everything except letters to securely match "Mon" or "Mon:"
          String textLetters = element.text.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
          if (dayMap.containsKey(textLetters)) {
            dayY[dayMap[textLetters]!] = element.boundingBox.center.dy;
          }

          // EXTRACT TIMES
          String textNormal = element.text.toLowerCase().replaceAll('o', '0');
          var tMatch = timeReg.firstMatch(textNormal);
          if (tMatch != null) {
            int hr = int.parse(tMatch.group(1)!);
            String? ampm = tMatch.group(2)?.replaceAll('.', '');
            
            if (ampm == 'pm' && hr < 12) hr += 12;
            if (ampm == 'am' && hr == 12) hr = 0;
            if (ampm == null && hr >= 1 && hr <= 7) hr += 12; 
            
            String timeStr = "${hr.toString().padLeft(2, '0')}:30";
            
            if (!colXList.containsKey(timeStr)) {
              colXList[timeStr] = [];
            }
            colXList[timeStr]!.add(element.boundingBox.center.dx);
          }
        }
      }
    }

    // THE FIX: Filter out classRects that geometrically overlap with an 'Online' marker
    classRects.removeWhere((classRect) {
      for (Rect onlineRect in onlineRects) {
        // If an online marker is in the exact same grid cell area, nuke the class
        bool sameColumn = (onlineRect.center.dx >= classRect.left - 150) && (onlineRect.center.dx <= classRect.right + 150);
        bool sameRow = (onlineRect.center.dy >= classRect.top - 200) && (onlineRect.center.dy <= classRect.bottom + 200);
        if (sameColumn && sameRow) return true;
      }
      return false;
    });

    // Average X coordinates to find the true center of each time column
    Map<String, double> finalColX = {};
    colXList.forEach((time, xList) {
      finalColX[time] = xList.reduce((a, b) => a + b) / xList.length;
    });

    if (dayY.isEmpty || finalColX.isEmpty || classRects.isEmpty) {
      _showFloatingSnackBar("Could not detect grid structure. Please select manually.", isError: true);
      return;
    }

    int slotsFound = 0;
    Map<String, List<String>> newSlots = Map.from(selectedSlots);
    var sortedTimes = finalColX.keys.toList()..sort();

    // Assign classes to slots based on geometric intersection
    for (Rect classRect in classRects) {
      // Find best Day based on relative vertical distance
      String? bestDay;
      double minDy = double.infinity;
      dayY.forEach((day, y) {
        double dist = (classRect.center.dy - y).abs();
        if (dist < minDy) {
          minDy = dist;
          bestDay = day;
        }
      });

      if (bestDay == null) continue; 

      // Find closest Start Time based on horizontal bounds
      String? bestTime;
      double minDx = double.infinity;
      for (String time in sortedTimes) {
        double x = finalColX[time]!;
        double dist = (classRect.left - x).abs();
        
        if (dist < minDx) {
          minDx = dist;
          bestTime = time;
        }
      }

      if (bestTime != null) { 
        for (String slot in timeSlots) {
          if (slot.startsWith(bestTime)) {
            if (!newSlots[bestDay]!.contains(slot)) {
              newSlots[bestDay]!.add(slot);
              slotsFound++;
            }
            break; // Stop after first hour to prevent double-booking recommendations
          }
        }
      }
    }

    // Trigger UI update
    if (slotsFound > 0) {
      setState(() => selectedSlots = newSlots);
      _showFloatingSnackBar("Success! Auto-selected $slotsFound physical class slots.");
      
      // Visually scroll to the first populated day to confirm success
      for (int i = 0; i < days.length; i++) {
        if (newSlots[days[i]]!.isNotEmpty) {
          _tabController.animateTo(i);
          break;
        }
      }
    } else {
      _showFloatingSnackBar("Detected text, but no physical classes found matching the grid.", isError: true);
    }
  }
  
  ================================================================================= */

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8F9FA),
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF262562)),
        centerTitle: true,
        title: const Text("My Timetable", style: TextStyle(color: Color(0xFF262562), fontWeight: FontWeight.w900, letterSpacing: -0.5)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: _isLoading 
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.0),
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Color(0xFF262562), strokeWidth: 3)),
                ) 
              : TextButton.icon(
                  icon: const Icon(Icons.check_rounded, color: Color(0xFF262562)),
                  label: const Text("Save", style: TextStyle(color: Color(0xFF262562), fontWeight: FontWeight.bold, fontSize: 16)),
                  onPressed: _saveTimetable,
                ),
          )
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))
              ],
            ),
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              dividerColor: Colors.transparent,
              indicatorPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: -10),
              labelColor: const Color(0xFF262562),
              unselectedLabelColor: Colors.grey.shade500,
              indicator: BoxDecoration(
                color: const Color(0xFF262562).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              tabs: days.map((day) => Tab(text: day)).toList(),
            ),
          ),
        ),
      ),
      /* ARCHIVED: Smart Scan Floating Action Button
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isScanning ? null : _showScanOptions,
        backgroundColor: const Color(0xFFF0AB00), 
        foregroundColor: Colors.white,
        elevation: 8,
        icon: _isScanning 
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
            : const Icon(Icons.document_scanner_rounded),
        label: Text(_isScanning ? "Scanning..." : "Smart Scan", style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
      ),
      */
      body: TabBarView(
        controller: _tabController,
        physics: const BouncingScrollPhysics(),
        children: days.map((day) {
          return _buildDayGrid(day);
        }).toList(),
      ),
    );
  }

  Widget _buildDayGrid(String day) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF262562).withOpacity(0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF262562).withOpacity(0.1)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline_rounded, color: Color(0xFF262562)),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "Tap the boxes below to mark your PHYSICAL classes for this day.",
                    style: TextStyle(color: Color(0xFF262562), fontSize: 13, fontWeight: FontWeight.w600, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2, 
              childAspectRatio: 2.5, 
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemCount: timeSlots.length,
            itemBuilder: (context, index) {
              final slot = timeSlots[index];
              final isSelected = selectedSlots[day]!.contains(slot);

              return GestureDetector(
                onTap: () => _toggleSlot(day, slot),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutQuint,
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFF262562) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected ? const Color(0xFF262562) : Colors.grey.shade300,
                      width: 1.5,
                    ),
                    boxShadow: isSelected 
                        ? [BoxShadow(color: const Color(0xFF262562).withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))]
                        : [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 5, offset: const Offset(0, 2))],
                  ),
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (isSelected) 
                          const Padding(
                            padding: EdgeInsets.only(right: 8.0),
                            child: Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                          ),
                        Text(
                          slot,
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.black87,
                            fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                            fontSize: 14,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 80), 
        ],
      ),
    );
  }
}