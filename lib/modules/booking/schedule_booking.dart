import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:campuspulse/modules/wallet/checkout_page.dart';

class ScheduleBooking extends StatefulWidget {
  final String zoneId;
  final String zoneName; 
  const ScheduleBooking({super.key, required this.zoneId, required this.zoneName});

  @override
  State<ScheduleBooking> createState() => _ScheduleBookingState();
}

class _ScheduleBookingState extends State<ScheduleBooking> {
  final User? user = FirebaseAuth.instance.currentUser;
  
  late Stream<QuerySnapshot> _allBookingsStream;

  String? selectedRouteId;
  String? selectedRouteName;
  
  // Explicit Dropoff Tracking
  List<Map<String, dynamic>> allRouteStops = [];
  List<Map<String, dynamic>> currentRouteStops = [];
  List<Map<String, dynamic>> validDropoffStops = [];
  
  String? selectedStopId;
  String? selectedStopName;
  String? selectedDropoffStopId;
  String? selectedDropoffStopName;

  // Date Selector State
  DateTime _selectedDate = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);

  @override
  void initState() {
    super.initState();
    _allBookingsStream = FirebaseFirestore.instance
        .collection('Bookings')
        .where('user_id', isEqualTo: user?.uid ?? '')
        .snapshots();
  }

  Future<String> _fetchDriverName(String driverId) async {
    if (driverId == 'TBD' || driverId.isEmpty) return 'To Be Determined';
    try {
      final doc = await FirebaseFirestore.instance.collection('Staffs').doc(driverId).get();
      if (doc.exists) return doc.data()?['name'] ?? doc.data()?['full_name'] ?? driverId;
    } catch (e) {
      debugPrint("Error fetching driver: $e");
    }
    return driverId; 
  }

  Future<void> _fetchStopsForRoute(Map<String, dynamic> routeData) async {
    try {
      List<dynamic> stopIdsDynamic = routeData['stop_ids'] ?? [];

      List<String> extractedStopIds = [];
      for (var item in stopIdsDynamic) {
        if (item is Map) extractedStopIds.add(item['stop_id'] as String);
        else if (item is String) extractedStopIds.add(item); 
      }
      
      if (extractedStopIds.isEmpty) return;

      final snapshot = await FirebaseFirestore.instance.collection('Stops').where(FieldPath.documentId, whereIn: extractedStopIds.take(10).toList()).get();

      List<Map<String, dynamic>> stops = [];
      for (var doc in snapshot.docs) stops.add({'id': doc.id, 'name': doc['name'] ?? 'Unknown Stop'});
      
      // Preserve the exact route order
      stops.sort((a, b) => extractedStopIds.indexOf(a['id']).compareTo(extractedStopIds.indexOf(b['id'])));

      if (mounted) {
        setState(() {
          allRouteStops = stops;
          
          // Pickup stops can be anything except the very last stop
          currentRouteStops = allRouteStops.length > 1 ? allRouteStops.sublist(0, allRouteStops.length - 1) : allRouteStops;
          
          if (selectedStopId == null || !currentRouteStops.any((s) => s['id'] == selectedStopId)) {
            selectedStopId = currentRouteStops.first['id'];
            selectedStopName = currentRouteStops.first['name'];
          }
          
          _updateValidDropoffs();
        });
      }
    } catch (e) { debugPrint("Error fetching stops: $e"); }
  }

  // Ensure Dropoff is strictly AFTER the Pickup stop
  void _updateValidDropoffs() {
    int pIndex = allRouteStops.indexWhere((s) => s['id'] == selectedStopId);
    if (pIndex != -1 && pIndex < allRouteStops.length - 1) {
        validDropoffStops = allRouteStops.sublist(pIndex + 1);
    } else {
        validDropoffStops = [];
    }
    
    // Default the dropoff to the absolute final destination of the route
    if (selectedDropoffStopId == null || !validDropoffStops.any((s) => s['id'] == selectedDropoffStopId)) {
        selectedDropoffStopId = validDropoffStops.isNotEmpty ? validDropoffStops.last['id'] : null;
        selectedDropoffStopName = validDropoffStops.isNotEmpty ? validDropoffStops.last['name'] : null;
    }
  }

  Future<void> _bookRide(DocumentSnapshot scheduleDoc, String pickupTime) async {
    final data = scheduleDoc.data() as Map<String, dynamic>;
    final String dateStr = data['date'] ?? 'Unknown Date';
    final String driverId = data['driver_id'] ?? 'TBD';
    
    String displayDriver = driverId;
    if (driverId != 'TBD') displayDriver = await _fetchDriverName(driverId);
    
    String displayDate = dateStr;
    try {
      final dt = DateTime.parse(dateStr);
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
          pickupStopId: selectedStopId ?? '',
          pickupStopName: selectedStopName ?? 'Selected Stop',
          dropoffStopId: selectedDropoffStopId,
          dropoffStopName: selectedDropoffStopName,
          scheduleDoc: scheduleDoc,
          routeId: selectedRouteId,
          routeName: selectedRouteName,
          pickupTime: pickupTime,
          date: data['date'],
          displayDate: displayDate,
          shuttleId: data['shuttle_id'],
          driverId: data['driver_id'],
          driverName: displayDriver,
        ),
      ),
    );

    if (result == 'goToTracking' && mounted) {
      Navigator.pop(context, 'goToTracking');
    }
  }

  Widget _buildRouteSelector(List<QueryDocumentSnapshot> routes) {
    if (selectedRouteId == null || routes.isEmpty) return const SizedBox.shrink();
    
    QueryDocumentSnapshot? selectedDoc;
    QueryDocumentSnapshot? otherDoc;

    for (var doc in routes) {
      final rId = (doc.data() as Map<String, dynamic>)['route_id'];
      if (rId == selectedRouteId) selectedDoc = doc;
      else otherDoc = doc;
    }

    selectedDoc ??= routes.first;
    otherDoc ??= routes.first;

    final selectedRouteData = selectedDoc.data() as Map<String, dynamic>;
    final bool isToCampus = selectedRouteData['direction'] == 'to_campus';

    return Container(
      margin: const EdgeInsets.fromLTRB(24, 16, 24, 10),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200, width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFF262562).withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(isToCampus ? Icons.school : Icons.home_work, color: const Color(0xFF262562), size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Direction", style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(isToCampus ? "To Campus" : "From Campus", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.black87)),
              ],
            ),
          ),
          if (routes.length > 1) 
            GestureDetector(
              onTap: () {
                setState(() {
                  selectedRouteId = (otherDoc!.data() as Map<String, dynamic>)['route_id'];
                  selectedRouteName = (otherDoc.data() as Map<String, dynamic>)['route_name'];
                  selectedStopId = null;
                  selectedDropoffStopId = null;
                  currentRouteStops.clear();
                  validDropoffStops.clear();
                });
                _fetchStopsForRoute(otherDoc!.data() as Map<String, dynamic>);
              },
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.grey.shade50, shape: BoxShape.circle, border: Border.all(color: Colors.grey.shade200)),
                child: const Icon(Icons.swap_vert_rounded, color: Color(0xFF262562), size: 20),
              ),
            ),
        ],
      ),
    );
  }

  void _showStopSelectorBottomSheet(bool isPickup) {
    final listToShow = isPickup ? currentRouteStops : validDropoffStops;
    final currentSelectedId = isPickup ? selectedStopId : selectedDropoffStopId;
    final title = isPickup ? "Select Pickup Stop" : "Select Dropoff Stop";

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(isPickup ? "Schedules will update based on the stop you select." : "Tell the driver where you want to get off.", style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 20),
            Flexible( 
              child: ListView.builder(
                shrinkWrap: true, 
                itemCount: listToShow.length,
                itemBuilder: (context, index) {
                  final stop = listToShow[index];
                  final isSelected = stop['id'] == currentSelectedId;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: isSelected ? const Color(0xFF262562) : Colors.grey.shade100, shape: BoxShape.circle),
                      child: Icon(isPickup ? Icons.my_location_rounded : Icons.location_on_rounded, color: isSelected ? Colors.white : Colors.grey, size: 20),
                    ),
                    title: Text(stop['name'], style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, color: isSelected ? const Color(0xFF262562) : Colors.black87)),
                    trailing: isSelected ? const Icon(Icons.check_circle, color: Color(0xFF262562)) : null,
                    onTap: () {
                      setState(() {
                        if (isPickup) {
                          selectedStopId = stop['id'];
                          selectedStopName = stop['name'];
                          _updateValidDropoffs(); // Re-calculate valid dropoffs if pickup changes
                        } else {
                          selectedDropoffStopId = stop['id'];
                          selectedDropoffStopName = stop['name'];
                        }
                      });
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Horizontal Date Selector UI
  Widget _buildDateSelector() {
    final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    // Generate the next 7 days for quick selection
    final List<DateTime> nextDays = List.generate(7, (i) => today.add(Duration(days: i)));

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
      height: 75,
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: nextDays.length,
              itemBuilder: (context, index) {
                final date = nextDays[index];
                final isSelected = date.year == _selectedDate.year && date.month == _selectedDate.month && date.day == _selectedDate.day;
                final isToday = index == 0;

                return GestureDetector(
                  onTap: () => setState(() => _selectedDate = date),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 62,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFF262562) : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: isSelected ? const Color(0xFF262562) : Colors.grey.shade200),
                      boxShadow: isSelected ? [BoxShadow(color: const Color(0xFF262562).withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))] : [],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          isToday ? "Today" : DateFormat('EEE').format(date), 
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isSelected ? Colors.white70 : Colors.grey.shade500)
                        ),
                        const SizedBox(height: 4),
                        Text(
                          DateFormat('dd').format(date), 
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: isSelected ? Colors.white : const Color(0xFF262562))
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _selectedDate,
                firstDate: today,
                lastDate: today.add(const Duration(days: 30)),
                builder: (context, child) {
                  return Theme(
                    data: Theme.of(context).copyWith(
                      colorScheme: const ColorScheme.light(
                        primary: Color(0xFF262562),
                        onPrimary: Colors.white,
                        onSurface: Colors.black87,
                      ),
                    ),
                    child: child!,
                  );
                },
              );
              if (picked != null) {
                setState(() => _selectedDate = picked);
              }
            },
            child: Container(
              width: 55,
              height: 75,
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: const Icon(Icons.calendar_month_rounded, color: Color(0xFF104C97)),
            ),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: _allBookingsStream,
      builder: (context, snapshot) {
        int scheduledCount = 0;
        Set<String> activeScheduleIds = {}; 
        
        if (snapshot.hasData) {
          for (var doc in snapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            final status = data['status'];
            final type = data['type'];
            if (type == 'scheduled' && ['pending', 'confirmed', 'arriving', 'on_board', 'onboard'].contains(status)) {
              scheduledCount++;
              if (data['schedule_id'] != null) {
                activeScheduleIds.add(data['schedule_id']);
              }
            }
          }
        }

        if (scheduledCount >= 3) {
          return Column(
            children: [
              Container(
                margin: const EdgeInsets.all(24),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.red.shade100), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 5))]),
                child: Column(
                  children: [
                    Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.red.shade50, shape: BoxShape.circle), child: const Icon(Icons.event_busy, color: Colors.redAccent, size: 30)),
                    const SizedBox(height: 16),
                    const Text("Booking Limit Reached", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 8),
                    Text("You already have $scheduledCount active scheduled bookings. Please complete or cancel a ride before booking another.", style: TextStyle(color: Colors.grey.shade600, fontSize: 13), textAlign: TextAlign.center),
                  ],
                ),
              ),
            ],
          );
        }

        return Column(
          children: [
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('Routes').where('zone_id', isEqualTo: widget.zoneId).where('status', isEqualTo: 'active').snapshots(),
              builder: (context, routeSnapshot) {
                if (routeSnapshot.hasError) return Center(child: Text("Error: ${routeSnapshot.error}"));
                if (routeSnapshot.connectionState == ConnectionState.waiting) return const Center(child: LinearProgressIndicator(color: Color(0xFFF0AB00)));
                if (!routeSnapshot.hasData || routeSnapshot.data!.docs.isEmpty) return const Padding(padding: EdgeInsets.all(40.0), child: Center(child: Text("No active routes found for this zone.", style: TextStyle(color: Colors.grey))));

                final routes = routeSnapshot.data!.docs;

                if (selectedRouteId == null && routes.isNotEmpty) {
                   Future.microtask(() {
                     if(mounted) {
                       setState(() {
                         selectedRouteId = routes.first['route_id'];
                         selectedRouteName = (routes.first.data() as Map)['route_name'];
                       });
                       _fetchStopsForRoute(routes.first.data() as Map<String, dynamic>);
                     }
                   });
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildRouteSelector(routes), 
                    
                    if (currentRouteStops.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white, 
                          borderRadius: BorderRadius.circular(20), 
                          border: Border.all(color: const Color(0xFF262562).withOpacity(0.2)), 
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))]
                        ),
                        child: Column(
                          children: [
                            InkWell(
                              onTap: () => _showStopSelectorBottomSheet(true),
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.green.shade50, shape: BoxShape.circle), child: const Icon(Icons.circle, color: Colors.green, size: 16)),
                                    const SizedBox(width: 12),
                                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("Pickup Location", style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600)), Text(selectedStopName ?? "Detecting...", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF262562)), overflow: TextOverflow.ellipsis)])),
                                    const Icon(Icons.keyboard_arrow_down, color: Colors.grey),
                                  ],
                                ),
                              ),
                            ),
                            const Divider(height: 1, indent: 50),
                            InkWell(
                              onTap: () => _showStopSelectorBottomSheet(false),
                              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.red.shade50, shape: BoxShape.circle), child: const Icon(Icons.square, color: Colors.redAccent, size: 16)),
                                    const SizedBox(width: 12),
                                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("Dropoff Location", style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600)), Text(selectedDropoffStopName ?? "Detecting...", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF262562)), overflow: TextOverflow.ellipsis)])),
                                    const Icon(Icons.keyboard_arrow_down, color: Colors.grey),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        )
                      ),
                      
                    if (currentRouteStops.isNotEmpty)
                      _buildDateSelector(),
                  ],
                );
              },
            ),

            Expanded(
              child: selectedRouteId == null || selectedStopId == null
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF262562)))
                : StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('Schedules').where('route_id', isEqualTo: selectedRouteId).where('status', isEqualTo: 'published').snapshots(),
                    builder: (context, scheduleSnapshot) {
                      if (scheduleSnapshot.hasError) return Center(child: Text("Error: ${scheduleSnapshot.error}"));
                      if (scheduleSnapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Color(0xFF262562)));
                      
                      final allDocs = scheduleSnapshot.data!.docs;
                      final now = DateTime.now();
                      
                      final String targetDateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);

                      final filteredDocs = allDocs.where((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final dateStr = data['date'] as String?;
                        final etas = data['etas'] as Map<String, dynamic>?;
                        if (dateStr == null || etas == null || !etas.containsKey(selectedStopId)) return false;

                        if (dateStr != targetDateStr) return false;

                        try {
                          final timeStr = etas[selectedStopId] ?? data['departure_time'] ?? '00:00';
                          final parts = timeStr.split(':');
                          final dt = DateTime.parse(dateStr);
                          final scheduleTime = DateTime(dt.year, dt.month, dt.day, int.parse(parts[0]), int.parse(parts[1]));
                          
                          if (scheduleTime.isBefore(now)) return false;
                        } catch (_) {}

                        return true;
                      }).toList();

                      if (filteredDocs.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.event_busy, size: 60, color: Colors.grey.shade300),
                              const SizedBox(height: 16),
                              Text("No shuttles found for ${DateFormat('dd MMM yyyy').format(_selectedDate)}.", style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
                            ],
                          )
                        );
                      }

                      filteredDocs.sort((a, b) {
                         final dataA = a.data() as Map<String, dynamic>;
                         final dataB = b.data() as Map<String, dynamic>;
                         final dateA = dataA['date'] ?? '';
                         final dateB = dataB['date'] ?? '';
                         int dateComp = dateA.compareTo(dateB);
                         if (dateComp != 0) return dateComp;
                         final etaA = (dataA['etas'] as Map)[selectedStopId] ?? '';
                         final etaB = (dataB['etas'] as Map)[selectedStopId] ?? '';
                         return etaA.compareTo(etaB);
                      });

                      return ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                        itemCount: filteredDocs.length,
                        itemBuilder: (context, index) {
                          final doc = filteredDocs[index];
                          final data = doc.data() as Map<String, dynamic>;
                          
                          final String dateStr = data['date'] ?? 'Unknown Date';
                          final Map<String, dynamic> etas = data['etas'] ?? {};
                          final String pickupTimeStr = etas[selectedStopId] ?? data['departure_time'] ?? '00:00';
                          
                          final int capacity = data['capacity'] ?? 13;
                          final int booked = data['booked_count'] ?? 0;
                          final int available = capacity - booked;
                          final bool isFull = available <= 0;
                          
                          final bool isAlreadyBooked = activeScheduleIds.contains(doc.id);

                          String displayDate = dateStr;
                          try { displayDate = DateFormat('MMM dd').format(DateTime.parse(dateStr)); } catch (_) {}

                          return Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 15, offset: const Offset(0, 8))]),
                            child: Material(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(24),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(24),
                                onTap: () {
                                  if (isAlreadyBooked) {
                                    Navigator.pop(context, 'goToTracking');
                                  } else if (!isFull) {
                                    _bookRide(doc, pickupTimeStr);
                                  }
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text("ETA", style: TextStyle(color: Colors.grey.shade500, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1)),
                                              const SizedBox(height: 4),
                                              Text(pickupTimeStr, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 32, color: Color(0xFF262562), height: 1)),
                                            ],
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                            decoration: BoxDecoration(
                                              color: isAlreadyBooked ? Colors.green.shade50 : (isFull ? Colors.red.shade50 : const Color(0xFFF0AB00).withOpacity(0.15)), 
                                              borderRadius: BorderRadius.circular(20)
                                            ),
                                            child: Text(
                                              isAlreadyBooked ? "BOOKED" : (isFull ? "FULL" : "$available Seats Left"), 
                                              style: TextStyle(
                                                color: isAlreadyBooked ? Colors.green.shade700 : (isFull ? Colors.red.shade700 : const Color(0xFFE69B00)), 
                                                fontWeight: FontWeight.w900, 
                                                fontSize: 13
                                              )
                                            ),
                                          )
                                        ],
                                      ),
                                      const SizedBox(height: 16),
                                      Row(
                                        children: [
                                          Icon(Icons.calendar_today, size: 16, color: Colors.grey.shade400),
                                          const SizedBox(width: 6),
                                          Text(displayDate, style: TextStyle(color: Colors.grey.shade600, fontSize: 13, fontWeight: FontWeight.w600)),
                                          const SizedBox(width: 16),
                                          Icon(Icons.directions_bus, size: 16, color: Colors.grey.shade400),
                                          const SizedBox(width: 6),
                                          Text("${data['shuttle_id'] ?? 'TBD'}", style: TextStyle(color: Colors.grey.shade600, fontSize: 13, fontWeight: FontWeight.w600)),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
            ),
          ],
        );
      },
    );
  }
}