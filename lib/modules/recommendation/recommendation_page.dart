import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:campuspulse/modules/recommendation/input_timetable_page.dart';
import 'package:campuspulse/modules/booking/booking_page.dart';
import 'package:intl/intl.dart';

class RecommendationPage extends StatefulWidget {
  final String zoneId;
  final String zoneName;

  const RecommendationPage({super.key, required this.zoneId, required this.zoneName});

  @override
  State<RecommendationPage> createState() => _RecommendationPageState();
}

class _RecommendationPageState extends State<RecommendationPage> {
  final User? user = FirebaseAuth.instance.currentUser;
  
  bool hasTimetable = false;
  Map<String, dynamic> timetable = {};
  
  // Cache for real schedules fetched from DB
  List<DocumentSnapshot> _zoneSchedules = [];
  
  bool isLoading = true;
  static bool _hasShownIntro = false; 

  @override
  void initState() {
    super.initState();
    _initData();
    
    if (!_hasShownIntro) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showSmartFeatureIntro();
        _hasShownIntro = true;
      });
    }
  }

  Future<void> _initData() async {
    setState(() => isLoading = true);
    await Future.wait([
      _fetchTimetable(),
      _fetchZoneSchedules(),
    ]);
    setState(() => isLoading = false);
  }

  Future<void> _fetchTimetable() async {
    if (user == null) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('Students').doc(user!.uid).get();
      if (doc.exists && doc.data()!.containsKey('timetable')) {
        Map<String, dynamic> data = doc.data()!['timetable'];
        bool hasAnySlot = false;
        data.forEach((key, value) {
          if (value is List && value.isNotEmpty) hasAnySlot = true;
        });

        setState(() {
          timetable = data;
          hasTimetable = hasAnySlot; 
        });
      }
    } catch (e) {
      debugPrint("Error fetching timetable: $e");
    }
  }

  // --- REVISED: Fetch Real Schedules via Route IDs ---
  Future<void> _fetchZoneSchedules() async {
    try {
      // 1. Fetch Routes for this Zone first
      final routesSnapshot = await FirebaseFirestore.instance
          .collection('Routes')
          .where('zone_id', isEqualTo: widget.zoneId)
          .where('status', isEqualTo: 'active')
          .get();

      if (routesSnapshot.docs.isEmpty) {
        debugPrint("DEBUG: No active routes found for zone ${widget.zoneId}");
        setState(() => _zoneSchedules = []);
        return;
      }

      // 2. Extract Route IDs
      final List<String> routeIds = routesSnapshot.docs
          .map((doc) => doc['route_id'] as String)
          .toList();

      if (routeIds.isEmpty) return;

      // 3. Fetch Schedules for these Routes
      // Note: 'whereIn' supports up to 10 values. Assuming a zone has fewer than 10 routes.
      final snapshot = await FirebaseFirestore.instance
          .collection('Schedules')
          .where('route_id', whereIn: routeIds) 
          .where('status', isEqualTo: 'published')
          .get();

      debugPrint("DEBUG: Fetched ${snapshot.docs.length} schedules for routes: $routeIds");
      setState(() {
        _zoneSchedules = snapshot.docs;
      });
    } catch (e) {
      debugPrint("Error fetching zone schedules: $e");
    }
  }

  void _showSmartFeatureIntro() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.auto_awesome, color: Colors.purple.shade400),
            const SizedBox(width: 10),
            const Text("Smart Trip Planner", style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Tired of guessing when to catch the shuttle?",
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
            SizedBox(height: 10),
            Text(
              "We analyze real-time schedules and traffic to give you two options:\n\n"
              "1. Best Scheduled Bus: The exact bus to book to arrive on time.\n"
              "2. On-Demand Time: The best time to request a ride if no bus fits.\n",
              style: TextStyle(height: 1.4, color: Colors.black87),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF104C97),
              foregroundColor: Colors.white,
            ),
            child: const Text("Let's Go!"),
          ),
        ],
      ),
    );
  }

  // --- LOGIC: Calculate Ideal Time ---
  DateTime? _calculateIdealDeparture(String day, String timeSlot) {
    try {
      final rawStart = timeSlot.split(' - ')[0]; // "08:30"
      final now = DateTime.now();
      int dayIndex = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"].indexOf(day);
      int todayIndex = now.weekday - 1; 
      int daysUntil = (dayIndex - todayIndex + 7) % 7;
      if (daysUntil == 0) daysUntil = 0; 

      final classDate = DateTime(now.year, now.month, now.day).add(Duration(days: daysUntil));
      
      TimeOfDay time;
      if (rawStart.contains("AM") || rawStart.contains("PM")) {
         final dt = DateFormat("hh:mm a").parse(rawStart.trim());
         time = TimeOfDay.fromDateTime(dt);
      } else {
         final parts = rawStart.trim().split(':');
         time = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
      }
      
      final classDateTime = DateTime(classDate.year, classDate.month, classDate.day, time.hour, time.minute);

      // Traffic Logic
      int travelMinutes = 30; 
      if ((classDateTime.hour >= 7 && classDateTime.hour <= 9) || 
          (classDateTime.hour >= 17 && classDateTime.hour <= 19)) {
        travelMinutes = 60; 
      }
      int bufferMinutes = 15; 
      
      return classDateTime.subtract(Duration(minutes: travelMinutes + bufferMinutes));
      
    } catch (e) {
      return null;
    }
  }

  // --- UPDATED LOGIC: Find Best Real Schedule (Nearest Appropriate) ---
  DocumentSnapshot? _findBestRealSchedule(DateTime idealDepartureTime) {
    DocumentSnapshot? bestMatch;
    Duration minDiff = const Duration(days: 1); // Start with a large difference

    for (var doc in _zoneSchedules) {
      final data = doc.data() as Map<String, dynamic>;
      
      final String? sDateStr = data['date'];
      final String? sTimeStr = data['departure_time'];
      
      if (sDateStr == null || sTimeStr == null) continue;
      
      try {
        final scheduleDate = DateTime.parse(sDateStr);
        
        // Match by Weekday (Relaxed matching for recurrent schedules)
        if (scheduleDate.weekday != idealDepartureTime.weekday) {
          continue; 
        }

        final timeParts = sTimeStr.split(':');
        
        // Normalize for time comparison
        final normalizedIdeal = DateTime(2000, 1, 1, idealDepartureTime.hour, idealDepartureTime.minute);
        final normalizedSchedule = DateTime(2000, 1, 1, int.parse(timeParts[0]), int.parse(timeParts[1]));

        // Calculate difference: Ideal - Schedule
        final diff = normalizedIdeal.difference(normalizedSchedule);

        // Criteria:
        // 1. Schedule must be BEFORE ideal time (or max 5 mins late) -> diff >= -5 mins
        // 2. Schedule must not be unreasonably early (e.g. > 4 hours early) -> diff < 240 mins
        if (diff.inMinutes >= -5 && diff.inMinutes < 240) {
          
          if (diff.abs() < minDiff.abs()) {
             // Check seats
             int seats = (data['capacity'] ?? 13) - (data['booked_count'] ?? 0);
             if (seats > 0) {
                minDiff = diff;
                bestMatch = doc;
             }
          }
        }
      } catch (e) {
        continue;
      }
    }
    return bestMatch;
  }

  // --- ACTION: Quick Book Logic ---
  Future<void> _handleQuickBook(DocumentSnapshot scheduleDoc) async {
    final data = scheduleDoc.data() as Map<String, dynamic>;
    final String routeId = data['route_id'];
    
    // Fetch Route Name for display
    String routeName = "Fixed Route";
    try {
      final routeDoc = await FirebaseFirestore.instance.collection('Routes').where('route_id', isEqualTo: routeId).limit(1).get();
      if (routeDoc.docs.isNotEmpty) {
        routeName = routeDoc.docs.first['route_name'] ?? routeName;
      }
    } catch (_) {}

    if (!mounted) return;

    // Show Confirmation
    bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Confirm Smart Booking"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Book this recommended ride?", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text("Route: $routeName"),
            Text("Date: ${data['date']}"),
            Text("Time: ${data['departure_time']}"),
            Text("Shuttle: ${data['shuttle_id'] ?? 'TBD'}"),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF104C97), foregroundColor: Colors.white),
            child: const Text("Confirm"),
          ),
        ],
      ),
    ) ?? false;

    if (!confirm) return;

    // Execute Transaction
    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final freshSnapshot = await transaction.get(scheduleDoc.reference);
        final freshData = freshSnapshot.data() as Map<String, dynamic>;
        
        final int freshBooked = freshData['booked_count'] ?? 0;
        final int freshCapacity = freshData['capacity'] ?? 13;

        if (freshBooked >= freshCapacity) {
          throw Exception("Seats no longer available");
        }

        transaction.update(scheduleDoc.reference, {
          'booked_count': freshBooked + 1
        });

        final bookingRef = FirebaseFirestore.instance.collection('Bookings').doc();
        transaction.set(bookingRef, {
          'user_id': user!.uid,
          'schedule_id': scheduleDoc.id,
          'route_id': routeId,
          'route_name': routeName,
          'type': 'scheduled',
          'status': 'confirmed',
          'booking_time': FieldValue.serverTimestamp(),
          'departure_time': data['departure_time'],
          'date': data['date'],
          'zone_id': widget.zoneId,
          'shuttle_id': data['shuttle_id'],
          'driver_id': data['driver_id'],
        });
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Booking Successful! Check 'My Bookings'.")));
        _fetchZoneSchedules(); 
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Booking failed: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.blue.shade50, Colors.white],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildAppBar(),
              Expanded(
                child: isLoading 
                    ? const Center(child: CircularProgressIndicator()) 
                    : !hasTimetable 
                        ? _buildEmptyState() 
                        : _buildRecommendationList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Color(0xFF104C97)),
                onPressed: () => Navigator.pop(context),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 15),
              const Text("Smart Planner", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF104C97))),
            ],
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                tooltip: "Clear Schedule",
                onPressed: _clearTimetable,
              ),
              IconButton(
                icon: const Icon(Icons.help_outline, color: Colors.grey),
                onPressed: _showSmartFeatureIntro,
              ),
              IconButton(
                icon: const Icon(Icons.edit_calendar, color: Color(0xFF104C97)),
                onPressed: () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => const InputTimetablePage()));
                  _initData(); 
                },
              ),
            ],
          )
        ],
      ),
    );
  }
  
  Future<void> _clearTimetable() async {
     bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Clear All Classes?"),
        content: const Text("This will remove your entire saved schedule."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Clear All"),
          ),
        ],
      ),
    ) ?? false;

    if (confirm) {
      setState(() => isLoading = true);
      await FirebaseFirestore.instance.collection('Students').doc(user!.uid).update({'timetable': {}});
      await _initData();
    }
  }

  Widget _buildEmptyState() {
     return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.2), blurRadius: 15, spreadRadius: 5)]),
              child: const Icon(Icons.calendar_month_rounded, size: 60, color: Color(0xFF104C97)),
            ),
            const SizedBox(height: 30),
            const Text("No Timetable Data", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87)),
            const SizedBox(height: 10),
            const Text("Add your class schedule to see smart recommendations.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 16)),
            const SizedBox(height: 40),
            ElevatedButton.icon(
              onPressed: () async {
                 await Navigator.push(context, MaterialPageRoute(builder: (_) => const InputTimetablePage()));
                 _initData();
              },
              icon: const Icon(Icons.add),
              label: const Text("Add Class Schedule"),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF0AB00), foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15)),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildRecommendationList() {
    List<Widget> cards = [];
    final days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

    for (var day in days) {
      if (timetable.containsKey(day) && (timetable[day] as List).isNotEmpty) {
        List<dynamic> slots = List.from(timetable[day]);
        slots.sort(); 
        
        for (var slot in slots) {
          DateTime? idealDeparture = _calculateIdealDeparture(day, slot.toString());
          if (idealDeparture == null) continue;

          // Find specific Real Schedule
          DocumentSnapshot? bestRealSchedule = _findBestRealSchedule(idealDeparture);

          cards.add(_buildClassSection(day, slot.toString(), idealDeparture, bestRealSchedule));
        }
      }
    }

    if (cards.isEmpty) return const Center(child: Text("No relevant upcoming classes found."));

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Padding(
           padding: EdgeInsets.only(bottom: 20),
           child: Text("Your Trip Plan", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87)),
        ),
        ...cards
      ],
    );
  }

  Widget _buildClassSection(String day, String classSlot, DateTime idealDeparture, DocumentSnapshot? bestSchedule) {
    final timeFormat = DateFormat("hh:mm a");
    bool isPeak = (idealDeparture.hour >= 7 && idealDeparture.hour <= 9) || (idealDeparture.hour >= 17 && idealDeparture.hour <= 19);
    
    // Calculate seats if schedule exists
    int seatsLeft = 0;
    if (bestSchedule != null) {
      final sData = bestSchedule.data() as Map<String, dynamic>;
      seatsLeft = (sData['capacity'] ?? 13) - (sData['booked_count'] ?? 0);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Class Header
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(4)),
              child: Text(day, style: TextStyle(color: Colors.grey.shade800, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 10),
            Text("Class: $classSlot", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            if (isPeak)
              Padding(
                 padding: const EdgeInsets.only(left: 10),
                 child: Text("Peak Traffic", style: TextStyle(fontSize: 12, color: Colors.orange.shade800, fontWeight: FontWeight.bold)),
              )
          ],
        ),
        const SizedBox(height: 12),

        // --- OPTION A: FIXED SCHEDULE ---
        if (bestSchedule != null)
           _buildOptionCard(
             title: "Option A: Scheduled Shuttle",
             time: (bestSchedule.data() as Map)['departure_time'] ?? "--:--",
             subtitle: "Shuttle ${(bestSchedule.data() as Map)['shuttle_id'] ?? ''} • $seatsLeft seats left",
             icon: Icons.directions_bus,
             color: const Color(0xFF104C97),
             onTap: () {
               // Direct Booking
               _handleQuickBook(bestSchedule);
             },
             isBest: true,
             buttonLabel: "Book This Bus",
           )
        else
           Container(
             margin: const EdgeInsets.only(bottom: 10),
             padding: const EdgeInsets.all(12),
             decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
             child: const Row(children: [
               Icon(Icons.warning_amber_rounded, color: Colors.grey),
               SizedBox(width: 10),
               Expanded(child: Text("No exact schedule found nearby.", style: TextStyle(color: Colors.grey))),
             ]),
           ),

        // --- OPTION B: ON-DEMAND ---
        _buildOptionCard(
          title: "Option B: On-Demand",
          time: timeFormat.format(idealDeparture),
          subtitle: "Recommended request time",
          icon: Icons.hail,
          color: Colors.orange.shade800,
          onTap: () {
             Navigator.push(context, MaterialPageRoute(builder: (_) => BookingPage(zoneId: widget.zoneId, zoneName: widget.zoneName, initialIndex: 1)));
          },
          isBest: bestSchedule == null, 
          buttonLabel: "Book On-Demand",
        ),
        
        const Divider(height: 40),
      ],
    );
  }

  Widget _buildOptionCard({required String title, required String time, required String subtitle, required IconData icon, required Color color, required VoidCallback onTap, bool isBest = false, String buttonLabel = "Book >"}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: isBest ? Border.all(color: color, width: 2) : Border.all(color: Colors.grey.shade200),
          boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.05), blurRadius: 5, offset: const Offset(0, 2))],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isBest) 
                     Container(
                       margin: const EdgeInsets.only(bottom: 4),
                       padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                       decoration: BoxDecoration(color: Colors.green.shade100, borderRadius: BorderRadius.circular(4)),
                       child: Text("BEST OPTION", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green.shade800)),
                     ),
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(time, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: color)),
                Text(buttonLabel, style: const TextStyle(color: Colors.grey, fontSize: 10)),
              ],
            )
          ],
        ),
      ),
    );
  }
}