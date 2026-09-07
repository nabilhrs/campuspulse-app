import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:campuspulse/modules/recommendation/input_timetable_page.dart';
import 'package:campuspulse/modules/booking/booking_page.dart';
import 'package:campuspulse/modules/wallet/checkout_page.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

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
  List<DocumentSnapshot> _zoneSchedules = [];
  bool isLoading = true;
  static bool _hasShownIntro = false; 

  int studentBuffer = 15; 
  int trafficDelayMinutes = 0;
  bool isTrafficDelay = false;
  
  Set<String> activeScheduleIds = {};

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
      _checkLiveTraffic(), 
      _fetchActiveBookings(),   
    ]);
    setState(() => isLoading = false);
  }

  Future<void> _fetchActiveBookings() async {
    if (user == null) return;
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('Bookings')
          .where('user_id', isEqualTo: user!.uid)
          .where('status', whereIn: ['pending', 'confirmed', 'arriving', 'on_board', 'onboard'])
          .get();

      Set<String> bookedIds = {};
      for (var doc in snapshot.docs) {
        final data = doc.data();
        if (data['type'] == 'scheduled' && data['schedule_id'] != null) {
          bookedIds.add(data['schedule_id']);
        }
      }
      
      if (mounted) {
        setState(() {
          activeScheduleIds = bookedIds;
        });
      }
    } catch (e) {
      debugPrint("Error fetching active bookings: $e");
    }
  }

  Future<void> _fetchTimetable() async {
    if (user == null) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('Students').doc(user!.uid).get();
      if (doc.exists) {
        final data = doc.data()!;
        
        studentBuffer = data['arrival_buffer'] ?? 15;

        if (data.containsKey('timetable')) {
          Map<String, dynamic> tData = data['timetable'];
          bool hasAnySlot = false;
          tData.forEach((key, value) {
            if (value is List && value.isNotEmpty) hasAnySlot = true;
          });

          setState(() {
            timetable = tData;
            hasTimetable = hasAnySlot; 
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching timetable: $e");
    }
  }

  Future<void> _checkLiveTraffic() async {
    try {
      final stopsSnap = await FirebaseFirestore.instance.collection('Stops')
          .where('status', isEqualTo: 'active')
          .where('zone_ids', arrayContains: widget.zoneId)
          .limit(1).get();
          
      if (stopsSnap.docs.isEmpty) return;
      
      final stopData = stopsSnap.docs.first.data();
      final double originLat = (stopData['lat'] is num) ? stopData['lat'].toDouble() : double.parse(stopData['lat'].toString());
      final double originLng = (stopData['lng'] is num) ? stopData['lng'].toDouble() : double.parse(stopData['lng'].toString());
      
      final String apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';
      if (apiKey.isEmpty) return;

      final uri = Uri.parse("https://routes.googleapis.com/directions/v2:computeRoutes");
      final body = {
        "origin": {"location": {"latLng": {"latitude": originLat, "longitude": originLng}}},
        "destination": {"location": {"latLng": {"latitude": 3.1592, "longitude": 101.7019}}}, // UniKL MIIT
        "travelMode": "DRIVE",
        "routingPreference": "TRAFFIC_AWARE",
      };

      final res = await http.post(uri, headers: {
         'Content-Type': 'application/json',
         'X-Goog-Api-Key': apiKey,
         'X-Goog-FieldMask': 'routes.duration,routes.staticDuration'
      }, body: json.encode(body));

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data['routes'] != null && data['routes'].isNotEmpty) {
           final route = data['routes'][0];
           int durationSec = int.parse(route['staticDuration'].replaceAll('s', ''));
           int trafficSec = int.parse(route['duration'].replaceAll('s', ''));
           
           if (trafficSec > durationSec + 300) { 
              setState(() {
                isTrafficDelay = true;
                trafficDelayMinutes = ((trafficSec - durationSec) / 60).round();
              });
              debugPrint("TRAFFIC DETECTED: Added $trafficDelayMinutes mins buffer.");
           }
        }
      }
    } catch (e) {
      debugPrint("Traffic API error: $e");
    }
  }

  Future<void> _fetchZoneSchedules() async {
    try {
      final routesSnapshot = await FirebaseFirestore.instance
          .collection('Routes')
          .where('zone_id', isEqualTo: widget.zoneId)
          .where('status', isEqualTo: 'active')
          .get();

      if (routesSnapshot.docs.isEmpty) {
        setState(() => _zoneSchedules = []);
        return;
      }

      final List<String> routeIds = routesSnapshot.docs
          .map((doc) => doc['route_id'] as String)
          .toList();

      if (routeIds.isEmpty) return;

      final snapshot = await FirebaseFirestore.instance
          .collection('Schedules')
          .where('route_id', whereIn: routeIds) 
          .where('status', isEqualTo: 'published')
          .get();

      setState(() {
        _zoneSchedules = snapshot.docs;
      });
    } catch (e) {
      debugPrint("Error fetching zone schedules: $e");
    }
  }

  void _showSmartFeatureIntro() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const SmartPlannerIntroPage(),
        fullscreenDialog: true,
      ),
    );
  }

  void _showPreferenceInfoDialog(BuildContext context) {
    int tempBuffer = studentBuffer;
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: const Row(
              children: [
                Icon(Icons.auto_awesome_motion, color: Color(0xFF262562)),
                SizedBox(width: 10),
                Text("Arrival Preference", style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF262562), fontSize: 18, letterSpacing: -0.5)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Your personalized buffer time. Select how early you want to arrive before class begins.",
                  style: TextStyle(fontSize: 14, color: Colors.black87, height: 1.5, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 16),
                
                _buildSelectableInfoRow(Icons.directions_run_rounded, "Just-in-time (5 min)", "Arrive exactly as class starts.", 5, tempBuffer, (val) {
                  setStateDialog(() => tempBuffer = (tempBuffer == val) ? 15 : val);
                }),
                _buildSelectableInfoRow(Icons.local_cafe_rounded, "Early Bird (30 min)", "Great for grabbing a coffee before class.", 30, tempBuffer, (val) {
                  setStateDialog(() => tempBuffer = (tempBuffer == val) ? 15 : val);
                }),
                
                const SizedBox(height: 12),
                
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50, 
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.shade100)
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline_rounded, size: 18, color: Colors.blue),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "Note: By default, the system applies a standard 15-minute buffer. Tap a selected option again to deselect and return to the default.",
                          style: TextStyle(color: Colors.blue.shade800, fontSize: 12, fontWeight: FontWeight.w600, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Cancel", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
              ),
              ElevatedButton(
                onPressed: isSaving ? null : () async {
                  if (tempBuffer == studentBuffer) {
                    Navigator.pop(context);
                    return;
                  }
                  
                  setStateDialog(() => isSaving = true);
                  
                  try {
                    await FirebaseFirestore.instance.collection('Students').doc(user!.uid).update({
                      'arrival_buffer': tempBuffer
                    });
                    
                    if (context.mounted) {
                      Navigator.pop(context); 
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Preferences updated! Recalculating routes..."), 
                          backgroundColor: Colors.green, 
                          behavior: SnackBarBehavior.floating
                        )
                      );
                      _initData(); 
                    }
                  } catch (e) {
                    setStateDialog(() => isSaving = false);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text("Failed to save: $e"), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating)
                      );
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF262562),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                ),
                child: isSaving 
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                  : const Text("Save & Apply", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        }
      ),
    );
  }

  Widget _buildSelectableInfoRow(IconData icon, String title, String desc, int value, int selectedValue, Function(int) onSelect) {
    bool isSelected = value == selectedValue;
    return GestureDetector(
      onTap: () => onSelect(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 12.0),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF262562).withOpacity(0.05) : Colors.transparent,
          border: Border.all(color: isSelected ? const Color(0xFF262562) : Colors.grey.shade200, width: 1.5),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: isSelected ? const Color(0xFF262562) : const Color(0xFFF0AB00)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: isSelected ? const Color(0xFF262562) : Colors.black87)),
                  const SizedBox(height: 2),
                  Text(desc, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                ],
              ),
            ),
            if (isSelected)
               const Icon(Icons.check_circle_rounded, color: Color(0xFF262562), size: 20)
          ],
        ),
      ),
    );
  }

  DateTime? _calculateIdealDeparture(String day, String timeSlot) {
    try {
      final rawStart = timeSlot.split(' - ')[0]; 
      final now = DateTime.now();
      int dayIndex = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"].indexOf(day);
      int todayIndex = now.weekday - 1; 
      int daysUntil = (dayIndex - todayIndex + 7) % 7;
      
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

      int travelMinutes = 30; 
      if ((classDateTime.hour >= 7 && classDateTime.hour <= 9) || 
          (classDateTime.hour >= 17 && classDateTime.hour <= 19)) {
        travelMinutes = 60; 
      }
      
      return classDateTime.subtract(Duration(minutes: travelMinutes + studentBuffer + trafficDelayMinutes));
    } catch (e) {
      return null;
    }
  }

  Map<String, dynamic>? _findBestRealSchedule(DateTime idealDepartureTime) {
    List<DocumentSnapshot> validFutureSchedules = [];
    final now = DateTime.now();
    
    DateTime safeIdealDeparture = idealDepartureTime;
    if (safeIdealDeparture.isBefore(now) && safeIdealDeparture.day != now.day) {
      safeIdealDeparture = safeIdealDeparture.add(const Duration(days: 7));
    }
    
    String idealDateString = DateFormat('yyyy-MM-dd').format(safeIdealDeparture);

    for (var doc in _zoneSchedules) {
      final data = doc.data() as Map<String, dynamic>;
      final String? sDateStr = data['date'];
      final String? sTimeStr = data['departure_time'];
      
      if (sDateStr == null || sTimeStr == null || sDateStr != idealDateString) continue;
      
      try {
        final timeParts = sTimeStr.split(':');
        final scheduleExactTime = DateTime(
          safeIdealDeparture.year, 
          safeIdealDeparture.month, 
          safeIdealDeparture.day, 
          int.parse(timeParts[0]), 
          int.parse(timeParts[1])
        );

        if (scheduleExactTime.isBefore(now.add(const Duration(minutes: 5)))) continue;

        final diffFromIdeal = safeIdealDeparture.difference(scheduleExactTime).inMinutes;
        
        if (diffFromIdeal > 180 || diffFromIdeal < -45) {
            continue; 
        }

        validFutureSchedules.add(doc);

      } catch (e) { continue; }
    }

    if (validFutureSchedules.isEmpty) return null;

    validFutureSchedules.sort((a, b) {
      final tAStr = (a.data() as Map)['departure_time'];
      final tBStr = (b.data() as Map)['departure_time'];
      
      final partsA = tAStr.split(':');
      final dtA = DateTime(safeIdealDeparture.year, safeIdealDeparture.month, safeIdealDeparture.day, int.parse(partsA[0]), int.parse(partsA[1]));
      
      final partsB = tBStr.split(':');
      final dtB = DateTime(safeIdealDeparture.year, safeIdealDeparture.month, safeIdealDeparture.day, int.parse(partsB[0]), int.parse(partsB[1]));
      
      final diffA = safeIdealDeparture.difference(dtA).inMinutes.abs();
      final diffB = safeIdealDeparture.difference(dtB).inMinutes.abs();
      
      int comparison = diffA.compareTo(diffB);
      if (comparison == 0) {
        return dtA.compareTo(dtB); 
      }
      return comparison;
    });

    DocumentSnapshot? absoluteClosest;
    DocumentSnapshot? nextBestAvailable;

    for (var doc in validFutureSchedules) {
      if (absoluteClosest == null) absoluteClosest = doc;
      
      final data = doc.data() as Map<String, dynamic>;
      int seats = (data['capacity'] ?? 13) - (data['booked_count'] ?? 0);
      
      if (seats > 0) {
        nextBestAvailable = doc;
        break; 
      }
    }

    if (nextBestAvailable == null) return null; 

    DocumentSnapshot? missedFull;
    if (absoluteClosest != null && absoluteClosest.id != nextBestAvailable.id) {
       missedFull = absoluteClosest;
    }

    return {
      'recommended': nextBestAvailable,
      'missedFull': missedFull,
    };
  }

  // --- THE FIX: Re-routed the One-Tap booking to use the authentic Checkout flow ---
  Future<void> _handleQuickBook(DocumentSnapshot scheduleDoc) async {
    final data = scheduleDoc.data() as Map<String, dynamic>;
    final String routeId = data['route_id'];
    
    String routeName = "Fixed Route";
    String pickupStopId = "";
    String dropoffStopId = "";

    try {
      final routeDoc = await FirebaseFirestore.instance.collection('Routes').where('route_id', isEqualTo: routeId).limit(1).get();
      if (routeDoc.docs.isNotEmpty) {
        routeName = routeDoc.docs.first['route_name'] ?? routeName;
        pickupStopId = routeDoc.docs.first['start_stop_id'] ?? "";
        dropoffStopId = routeDoc.docs.first['end_stop_id'] ?? "";
      }
    } catch (_) {}

    String pickupStopName = "Zone Pickup";
    String dropoffStopName = "UniKL MIIT (Campus)";

    try {
      if (pickupStopId.isNotEmpty) {
        final pDoc = await FirebaseFirestore.instance.collection('Stops').doc(pickupStopId).get();
        if (pDoc.exists) pickupStopName = pDoc.data()?['name'] ?? pickupStopName;
      }
      if (dropoffStopId.isNotEmpty) {
        final dDoc = await FirebaseFirestore.instance.collection('Stops').doc(dropoffStopId).get();
        if (dDoc.exists) dropoffStopName = dDoc.data()?['name'] ?? dropoffStopName;
      }
    } catch (_) {}

    if (!mounted) return;

    final String driverId = data['driver_id'] ?? 'TBD';
    String displayDriver = driverId;
    if (driverId != 'TBD') {
      try {
        final dDoc = await FirebaseFirestore.instance.collection('Staffs').doc(driverId).get();
        if (dDoc.exists) {
          displayDriver = dDoc.data()?['name'] ?? dDoc.data()?['full_name'] ?? driverId;
        }
      } catch (_) {}
    }

    String displayDate = data['date'] ?? 'Unknown Date';
    try {
      final dt = DateTime.parse(displayDate);
      displayDate = DateFormat('EEE, dd MMM yyyy').format(dt);
    } catch (_) {}

    if (!mounted) return;

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CheckoutPage(
          tripType: 'scheduled',
          zoneId: widget.zoneId,
          zoneName: widget.zoneName,
          pickupStopId: pickupStopId,
          pickupStopName: pickupStopName,
          dropoffStopId: dropoffStopId,
          dropoffStopName: dropoffStopName,
          scheduleDoc: scheduleDoc,
          routeId: routeId,
          routeName: routeName,
          pickupTime: data['departure_time'],
          date: data['date'],
          displayDate: displayDate,
          shuttleId: data['shuttle_id'],
          driverId: driverId,
          driverName: displayDriver,
        ),
      ),
    );

    if (result == 'goToTracking' && mounted) {
      Navigator.pop(context, 'goToTracking'); 
      _fetchActiveBookings();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8F9FA),
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF262562)),
        title: const Text("Smart Planner", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF262562), letterSpacing: -0.5)),
        centerTitle: true,
        actions: [
          if (hasTimetable)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              tooltip: "Clear Schedule",
              onPressed: _clearTimetable,
            ),
          IconButton(
            icon: Icon(Icons.help_outline_rounded, color: Colors.purple.shade400),
            onPressed: _showSmartFeatureIntro,
          ),
          IconButton(
            icon: const Icon(Icons.edit_calendar, color: Color(0xFF262562)),
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const InputTimetablePage()));
              _initData(); 
            },
          ),
        ],
      ),
      body: SafeArea(
        child: isLoading 
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF262562))) 
            : !hasTimetable 
                ? _buildModernEmptyState() 
                : _buildRecommendationList(),
      ),
    );
  }
  
  Future<void> _clearTimetable() async {
    bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text("Clear All Classes?", style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text("This will remove your entire saved schedule."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel", style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
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

  Widget _buildModernEmptyState() {
     return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.white, 
                shape: BoxShape.circle, 
                boxShadow: [BoxShadow(color: const Color(0xFF262562).withOpacity(0.1), blurRadius: 30, offset: const Offset(0, 10))]
              ),
              child: const Icon(Icons.edit_calendar_rounded, size: 80, color: Color(0xFF262562)),
            ),
            const SizedBox(height: 36),
            const Text("Your Planner is Empty", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF262562), letterSpacing: -0.5)),
            const SizedBox(height: 12),
            const Text(
              "Add your class schedule to let CampusPulse automatically find the best shuttles for you.", 
              textAlign: TextAlign.center, 
              style: TextStyle(color: Colors.grey, fontSize: 16, height: 1.4)
            ),
            const SizedBox(height: 48),
            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton.icon(
                onPressed: () async {
                   await Navigator.push(context, MaterialPageRoute(builder: (_) => const InputTimetablePage()));
                   _initData();
                },
                icon: const Icon(Icons.add_rounded),
                label: const Text("Add Class Schedule", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF262562), 
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  elevation: 8,
                  shadowColor: const Color(0xFF262562).withOpacity(0.4)
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildRecommendationList() {
    final now = DateTime.now();
    List<Map<String, dynamic>> upcomingClasses = [];

    timetable.forEach((day, slots) {
      if (slots is List && slots.isNotEmpty) {
        for (var slot in slots) {
          DateTime? idealDeparture = _calculateIdealDeparture(day, slot.toString());
          if (idealDeparture != null) {
            
            if (idealDeparture.isBefore(now) && idealDeparture.day != now.day) {
              idealDeparture = idealDeparture.add(const Duration(days: 7));
            }
            upcomingClasses.add({
              'day': day,
              'slot': slot.toString(),
              'idealDeparture': idealDeparture,
            });
          }
        }
      }
    });

    upcomingClasses.sort((a, b) => (a['idealDeparture'] as DateTime).compareTo(b['idealDeparture'] as DateTime));

    List<Widget> cards = [];
    for (var classInfo in upcomingClasses) {
      DateTime idealDeparture = classInfo['idealDeparture'];
      Map<String, dynamic>? recommendationData = _findBestRealSchedule(idealDeparture);
      
      cards.add(_buildClassSection(classInfo['day'], classInfo['slot'], idealDeparture, recommendationData));
    }

    if (cards.isEmpty) return const Center(child: Text("No relevant upcoming classes found."));

    return ListView(
      padding: const EdgeInsets.all(24),
      physics: const BouncingScrollPhysics(),
      children: [
        if (isTrafficDelay)
          Container(
            margin: const EdgeInsets.only(bottom: 24),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(16)),
            child: Row(
              children: [
                const Icon(Icons.traffic_rounded, color: Colors.orange, size: 24),
                const SizedBox(width: 12),
                Expanded(child: Text("Heavy traffic detected. We've added $trafficDelayMinutes mins to your recommended departure times.", style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 13))),
              ],
            )
          ),

        Padding(
           padding: const EdgeInsets.only(bottom: 24),
           child: Row(
             mainAxisAlignment: MainAxisAlignment.spaceBetween,
             children: [
               const Text("Your Trip Plan", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF262562), letterSpacing: -0.5)),
               GestureDetector(
                 onTap: () => _showPreferenceInfoDialog(context),
                 child: Container(
                   padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                   decoration: BoxDecoration(
                     color: const Color(0xFF262562).withOpacity(0.1),
                     borderRadius: BorderRadius.circular(20),
                   ),
                   child: Row(
                     children: [
                       Text("Buffer: $studentBuffer min", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF262562))),
                       const SizedBox(width: 6),
                       const Icon(Icons.edit_rounded, size: 14, color: Color(0xFF262562)),
                     ],
                   ),
                 ),
               ),
             ],
           ),
        ),
        ...cards
      ],
    );
  }

  Widget _buildClassSection(String day, String classSlot, DateTime idealDeparture, Map<String, dynamic>? recommendationData) {
    final timeFormat = DateFormat("hh:mm a");
    bool isPeak = (idealDeparture.hour >= 7 && idealDeparture.hour <= 9) || (idealDeparture.hour >= 17 && idealDeparture.hour <= 19);
    
    DocumentSnapshot? bestSchedule = recommendationData?['recommended'];
    DocumentSnapshot? missedFull = recommendationData?['missedFull'];

    bool onDemandRestricted = isPeak && bestSchedule != null;

    int seatsLeft = 0;
    bool isBestScheduleBooked = false; // --- THE FIX: Validation flag ---
    
    if (bestSchedule != null) {
      final sData = bestSchedule.data() as Map<String, dynamic>;
      seatsLeft = (sData['capacity'] ?? 13) - (sData['booked_count'] ?? 0);
      isBestScheduleBooked = activeScheduleIds.contains(bestSchedule.id);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 36.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)),
                child: Text(day, style: TextStyle(color: Colors.grey.shade800, fontWeight: FontWeight.w900)),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text("Class: $classSlot", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Colors.black87), overflow: TextOverflow.ellipsis)),
            ],
          ),
          
          if (isPeak)
            Padding(
               padding: const EdgeInsets.only(top: 8, bottom: 4),
               child: Row(
                 children: [
                   Icon(Icons.trending_up_rounded, size: 16, color: Colors.orange.shade800),
                   const SizedBox(width: 6),
                   Text("Peak Hour Traffic Expected", style: TextStyle(fontSize: 13, color: Colors.orange.shade800, fontWeight: FontWeight.bold)),
                 ],
               ),
            )
          else
            const SizedBox(height: 16),

          if (missedFull != null)
             Container(
               margin: const EdgeInsets.only(bottom: 12),
               padding: const EdgeInsets.all(12),
               decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.orange.shade200)),
               child: Row(
                 children: [
                   const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
                   const SizedBox(width: 8),
                   Expanded(child: Text("Heads up! The ${(missedFull.data() as Map)['departure_time']} shuttle is full. We have automatically recommended the next best slot below.", style: const TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.bold))),
                 ],
               ),
             ),

          // OPTION A: SCHEDULED SHUTTLE
          // --- THE FIX: Transform the UI & logic if the user already booked this exact shuttle ---
          if (bestSchedule != null)
             _buildOptionCard(
               title: "Option A: Scheduled Shuttle",
               time: (bestSchedule.data() as Map)['departure_time'] ?? "--:--",
               subtitle: "Shuttle ${(bestSchedule.data() as Map)['shuttle_id'] ?? ''} • $seatsLeft seats left",
               icon: isBestScheduleBooked ? Icons.check_circle_rounded : Icons.directions_bus_rounded,
               color: isBestScheduleBooked ? Colors.green.shade700 : const Color(0xFF262562),
               onTap: () {
                 if (isBestScheduleBooked) {
                    Navigator.pop(context, 'goToTracking'); // Route to tracking instead of checkout
                 } else {
                    _handleQuickBook(bestSchedule);
                 }
               },
               isBest: true,
               buttonLabel: isBestScheduleBooked ? "Track Ride" : "Book Seat",
               isAlreadyBooked: isBestScheduleBooked,
             )
          else
             Container(
               margin: const EdgeInsets.only(bottom: 12),
               padding: const EdgeInsets.all(16),
               decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(16)),
               child: const Row(children: [
                 Icon(Icons.search_off_rounded, color: Colors.grey),
                 SizedBox(width: 12),
                 Expanded(child: Text("No upcoming scheduled shuttle found for this time.", style: TextStyle(color: Colors.grey))),
               ]),
             ),

          // OPTION B: ON-DEMAND
          _buildOptionCard(
            title: "Option B: On-Demand",
            time: timeFormat.format(idealDeparture),
            subtitle: onDemandRestricted 
                ? "Restricted during Peak Hour shuttles" 
                : "Recommended request time",
            icon: onDemandRestricted ? Icons.lock_outline_rounded : Icons.hail_rounded,
            color: onDemandRestricted ? Colors.grey : Colors.orange.shade800,
            onTap: onDemandRestricted ? () {} : () {
               Navigator.push(context, MaterialPageRoute(builder: (_) => BookingPage(zoneId: widget.zoneId, zoneName: widget.zoneName, initialIndex: 1)));
            },
            isBest: bestSchedule == null, 
            buttonLabel: onDemandRestricted ? "Locked" : "Request Now",
            isDisabled: onDemandRestricted,
          ),
        ],
      ),
    );
  }

  Widget _buildOptionCard({
    required String title, 
    required String time, 
    required String subtitle, 
    required IconData icon, 
    required Color color, 
    required VoidCallback onTap, 
    bool isBest = false, 
    String buttonLabel = "Book >",
    bool isDisabled = false,
    bool isAlreadyBooked = false, // --- THE FIX: Passed flag down to child widget ---
  }) {
    return GestureDetector(
      onTap: isDisabled ? null : onTap,
      child: Opacity(
        opacity: isDisabled ? 0.6 : 1.0,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: isBest && !isDisabled ? Border.all(color: color, width: 2) : Border.all(color: Colors.transparent),
            boxShadow: [
              if (isBest && !isDisabled) BoxShadow(color: color.withOpacity(0.15), blurRadius: 20, offset: const Offset(0, 8))
              else BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4)),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isBest && !isDisabled) 
                       Container(
                         margin: const EdgeInsets.only(bottom: 6),
                         padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                         decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
                         child: Text(isAlreadyBooked ? "BOOKED" : "RECOMMENDED", style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.5)),
                       ),
                    Text(title, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: isDisabled ? Colors.grey : Colors.black)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(color: isDisabled ? Colors.red.shade300 : Colors.grey.shade600, fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(time, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: color)),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(color: isDisabled ? Colors.grey.shade200 : Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
                    child: Text(buttonLabel, style: TextStyle(color: isDisabled ? Colors.grey.shade600 : Colors.grey.shade800, fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}

class SmartPlannerIntroPage extends StatelessWidget {
  const SmartPlannerIntroPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Skip", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          )
        ],
      ),
      extendBodyBehindAppBar: true,
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(top: 80, bottom: 40),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF262562), Color(0xFF0A3060)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(40), bottomRight: Radius.circular(40)),
              boxShadow: [BoxShadow(color: const Color(0xFF262562).withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10))],
            ),
            child: Column(
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(width: 120, height: 120, decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), shape: BoxShape.circle)),
                    Container(width: 90, height: 90, decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle)),
                    const Icon(Icons.auto_awesome_rounded, size: 50, color: Color(0xFFF0AB00)),
                  ],
                ),
                const SizedBox(height: 24),
                const Text("Smart Trip Planner", style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5)),
                const SizedBox(height: 8),
                Text(
                  "Never guess when to catch the shuttle again.",
                  style: TextStyle(fontSize: 16, color: Colors.white.withOpacity(0.9), fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
              child: Column(
                children: [
                  _buildFeatureRow(
                    icon: Icons.edit_calendar_rounded,
                    color: Colors.blue,
                    title: "Sync Your Classes",
                    description: "Input your timetable once. We'll track exactly when you need to be at UniKL MIIT.",
                  ),
                  const SizedBox(height: 32),
                  _buildFeatureRow(
                    icon: Icons.psychology_rounded,
                    color: Colors.purple,
                    title: "Predictive Trip Logic",
                    description: "We analyze real-time active schedules, capacity, and peak hour traffic to calculate your ideal departure time.",
                  ),
                  const SizedBox(height: 32),
                  
                  // --- THE NEW FEATURE ROW ---
                  _buildFeatureRow(
                    icon: Icons.tune_rounded,
                    color: Colors.orange,
                    title: "Arrival Preference",
                    description: "By default, we ensure you arrive 15 mins early. You can customize this to 5 mins (Just-in-time) or 30 mins (Early Bird) anytime.",
                  ),
                  
                  const SizedBox(height: 32),
                  _buildFeatureRow(
                    icon: Icons.check_circle_outline_rounded,
                    color: Colors.green,
                    title: "One-Tap Booking",
                    description: "Review our top recommended options and secure your seat on the best shuttle instantly.",
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(32.0),
            child: SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF262562),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  elevation: 5,
                  shadowColor: const Color(0xFF262562).withOpacity(0.4),
                ),
                child: const Text("Let's Get Started", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildFeatureRow({required IconData icon, required Color color, required String title, required String description}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
          child: Icon(icon, size: 32, color: color),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black87)),
              const SizedBox(height: 6),
              Text(description, style: TextStyle(fontSize: 14, color: Colors.grey.shade600, height: 1.4, fontWeight: FontWeight.w500)),
            ],
          ),
        )
      ],
    );
  }
}