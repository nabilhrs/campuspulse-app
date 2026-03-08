import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class InputTimetablePage extends StatefulWidget {
  const InputTimetablePage({super.key});

  @override
  State<InputTimetablePage> createState() => _InputTimetablePageState();
}

class _InputTimetablePageState extends State<InputTimetablePage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final User? user = FirebaseAuth.instance.currentUser;
  bool _isLoading = false;

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

  Future<void> _saveTimetable() async {
    setState(() => _isLoading = true);
    try {
      await FirebaseFirestore.instance.collection('Students').doc(user!.uid).set({
        'timetable': selectedSlots
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Class schedule saved successfully!")));
        Navigator.pop(context); 
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error saving: $e")));
    } finally {
      setState(() => _isLoading = false);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text("My Timetable", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF104C97),
        foregroundColor: Colors.white,
        centerTitle: true,
        actions: [
          IconButton(
            icon: _isLoading 
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
              : const Icon(Icons.check),
            onPressed: _isLoading ? null : _saveTimetable,
            tooltip: "Save Schedule",
          )
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              labelColor: const Color(0xFF104C97),
              unselectedLabelColor: Colors.grey,
              indicatorColor: const Color(0xFFF0AB00),
              indicatorWeight: 3,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              tabs: days.map((day) => Tab(text: day)).toList(),
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: days.map((day) {
          return _buildDayGrid(day);
        }).toList(),
      ),
    );
  }

  Widget _buildDayGrid(String day) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Instructional Text
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.shade100),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: Color(0xFF104C97)),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "Tap the boxes below to mark your PHYSICAL classes for this day.",
                    style: TextStyle(color: Color(0xFF104C97), fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Grid of Time Slots
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2, // 2 columns for clear readability
              childAspectRatio: 2.5, // Wide rectangular look
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: timeSlots.length,
            itemBuilder: (context, index) {
              final slot = timeSlots[index];
              final isSelected = selectedSlots[day]!.contains(slot);

              return GestureDetector(
                onTap: () => _toggleSlot(day, slot),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFF104C97) : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? const Color(0xFF104C97) : Colors.grey.shade300,
                      width: 2,
                    ),
                    boxShadow: isSelected 
                        ? [BoxShadow(color: const Color(0xFF104C97).withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))]
                        : [],
                  ),
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (isSelected) 
                          const Padding(
                            padding: EdgeInsets.only(right: 8.0),
                            child: Icon(Icons.check, color: Colors.white, size: 18),
                          ),
                        Text(
                          slot,
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.grey.shade700,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}