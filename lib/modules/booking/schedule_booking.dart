import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class ScheduleBooking extends StatefulWidget {
  final String zoneId;
  const ScheduleBooking({super.key, required this.zoneId});

  @override
  State<ScheduleBooking> createState() => _ScheduleBookingState();
}

class _ScheduleBookingState extends State<ScheduleBooking> {
  final User? user = FirebaseAuth.instance.currentUser;
  
  // State for Route Selection
  String? selectedRouteId;
  String? selectedRouteName;

  // --- Helper: Fetch Driver Name ---
  Future<String> _fetchDriverName(String driverId) async {
    if (driverId == 'TBD' || driverId.isEmpty) return 'To Be Determined';
    try {
      final doc = await FirebaseFirestore.instance.collection('Staffs').doc(driverId).get();
      if (doc.exists) {
        final data = doc.data();
        return data?['name'] ?? data?['full_name'] ?? driverId;
      }
    } catch (e) {
      debugPrint("Error fetching driver: $e");
    }
    return driverId; 
  }

  // --- Booking Logic ---
  Future<void> _bookRide(DocumentSnapshot scheduleDoc) async {
    final scheduleId = scheduleDoc.id;
    final data = scheduleDoc.data() as Map<String, dynamic>;
    
    // 1. Prepare Data for Confirmation Dialog
    final String dateStr = data['date'] ?? 'Unknown Date';
    final String timeStr = data['departure_time'] ?? '00:00';
    final String shuttleId = data['shuttle_id'] ?? 'TBD';
    final String driverId = data['driver_id'] ?? 'TBD';
    
    // FETCH THE DRIVER NAME HERE
    String displayDriver = driverId;
    if (driverId != 'TBD') {
      displayDriver = await _fetchDriverName(driverId);
    }
    
    // Format Date for display
    String displayDate = dateStr;
    try {
      final dt = DateTime.parse(dateStr);
      displayDate = DateFormat('EEE, dd MMM yyyy').format(dt);
    } catch (_) {}

    if (!mounted) return;

    // 2. Show Confirmation Dialog
    bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Confirm Booking Details"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow(Icons.map, "Route", selectedRouteName ?? "Selected Route"),
            const SizedBox(height: 10),
            _buildDetailRow(Icons.calendar_today, "Date", displayDate),
            const SizedBox(height: 10),
            _buildDetailRow(Icons.access_time, "Time", timeStr),
            const SizedBox(height: 10),
            _buildDetailRow(Icons.directions_bus, "Shuttle", shuttleId),
            const SizedBox(height: 10),
            _buildDetailRow(Icons.person, "Driver", displayDriver), 
            const SizedBox(height: 20),
            const Text(
              "Please ensure you are at the pickup point 10 minutes before departure.",
              style: TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF104C97),
              foregroundColor: Colors.white,
            ),
            child: const Text("Confirm Booking"),
          ),
        ],
      ),
    ) ?? false;

    if (!confirm) return;

    // 3. Proceed with Transaction
    final int capacity = data['capacity'] ?? 13;
    final int bookedCount = data['booked_count'] ?? 0;

    if (bookedCount >= capacity) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Shuttle is full!")));
      return;
    }

    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final freshSnapshot = await transaction.get(scheduleDoc.reference);
        final freshData = freshSnapshot.data() as Map<String, dynamic>;
        
        final int freshBooked = freshData['booked_count'] ?? 0;
        final int freshCapacity = freshData['capacity'] ?? 13;

        if (freshBooked >= freshCapacity) {
          throw Exception("Seats no longer available");
        }

        // Increment booked_count
        transaction.update(scheduleDoc.reference, {
          'booked_count': freshBooked + 1
        });

        // Create Booking Record
        final bookingRef = FirebaseFirestore.instance.collection('Bookings').doc();
        transaction.set(bookingRef, {
          'user_id': user!.uid,
          'schedule_id': scheduleId,
          'route_id': selectedRouteId,
          'route_name': selectedRouteName, 
          'type': 'scheduled',
          'status': 'confirmed',
          'booking_time': FieldValue.serverTimestamp(),
          'departure_time': data['departure_time'],
          'date': data['date'],
          'zone_id': widget.zoneId,
          'shuttle_id': data['shuttle_id'],
          'driver_id': data['driver_id'],
          'driver_name': displayDriver, 
        });
      });

      if(mounted) {
        showDialog(
          context: context, 
          builder: (_) => AlertDialog(
            title: const Text("Booking Successful"),
            content: const Text("Your seat has been reserved. You can view your ticket in 'My Bookings' or 'Tracking'."),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("OK"))],
          )
        );
      }

    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Booking failed: $e")));
    }
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: const Color(0xFF104C97)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 1. Route Selection Dropdown
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('Routes')
              .where('zone_id', isEqualTo: widget.zoneId)
              .where('status', isEqualTo: 'active')
              .snapshots(),
          builder: (context, routeSnapshot) {
            if (routeSnapshot.hasError) return Center(child: Text("Error: ${routeSnapshot.error}"));
            if (routeSnapshot.connectionState == ConnectionState.waiting) return const Center(child: LinearProgressIndicator());
            
            if (!routeSnapshot.hasData || routeSnapshot.data!.docs.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(20.0),
                child: Center(child: Text("No active routes found for this zone.")),
              );
            }

            // Create dropdown items
            final routes = routeSnapshot.data!.docs;
            final items = routes.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              return DropdownMenuItem<String>(
                value: data['route_id'],
                child: Text(data['route_name'] ?? 'Unnamed Route'),
              );
            }).toList();

            // Auto-select if only one route, or if previous selection invalid
            if (selectedRouteId == null && routes.length == 1) {
               Future.microtask(() {
                 setState(() {
                   selectedRouteId = routes.first['route_id'];
                   selectedRouteName = routes.first['route_name'];
                 });
               });
            }

            return Container(
              padding: const EdgeInsets.all(16),
              color: Colors.blue.shade50,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Select Route", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF104C97))),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: selectedRouteId,
                    hint: const Text("Choose a route..."),
                    isExpanded: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      fillColor: Colors.white,
                      filled: true,
                    ),
                    items: items,
                    onChanged: (val) {
                      setState(() {
                        selectedRouteId = val;
                        // Find name
                        final selectedDoc = routes.firstWhere((doc) => doc['route_id'] == val);
                        selectedRouteName = selectedDoc['route_name'];
                      });
                    },
                  ),
                ],
              ),
            );
          },
        ),

        // 2. Fetch Schedules for Selected Route
        Expanded(
          child: selectedRouteId == null 
            ? const Center(child: Text("Please select a route above to view schedules.", style: TextStyle(color: Colors.grey)))
            : StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('Schedules')
                    .where('route_id', isEqualTo: selectedRouteId)
                    .where('status', isEqualTo: 'published')
                    .snapshots(),
                builder: (context, scheduleSnapshot) {
                  if (scheduleSnapshot.hasError) return Center(child: Text("Error: ${scheduleSnapshot.error}"));
                  if (scheduleSnapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                  
                  final allDocs = scheduleSnapshot.data!.docs;
                  
                  // --- FILTER LOGIC ---
                  final filteredDocs = allDocs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final dateStr = data['date'] as String?;
                    if (dateStr == null) return false;
                    
                    try {
                      final date = DateTime.parse(dateStr);
                      
                      // 1. Must be Mon(1) - Thu(4)
                      // COMMENTED OUT to allow seeing Fri-Sun schedules for testing
                      // if (date.weekday > 4) {
                      //   debugPrint("Skipped schedule on ${date.weekday} (Fri-Sun)");
                      //   return false;
                      // }
                      
                      // 2. Must be Today or Future (Uncomment for production)
                      /*
                      final today = DateTime.now();
                      final justDate = DateTime(today.year, today.month, today.day);
                      if (date.isBefore(justDate)) return false;
                      */

                      return true;
                    } catch (e) {
                      return false; 
                    }
                  }).toList();

                  if (filteredDocs.isEmpty) {
                    return const Center(child: Text("No upcoming schedules for this route."));
                  }

                  // Sort Logic
                  filteredDocs.sort((a, b) {
                     final dateA = (a.data() as Map)['date'] ?? '';
                     final dateB = (b.data() as Map)['date'] ?? '';
                     int dateComp = dateA.compareTo(dateB);
                     if (dateComp != 0) return dateComp;
                     
                     final timeA = (a.data() as Map)['departure_time'] ?? '';
                     final timeB = (b.data() as Map)['departure_time'] ?? '';
                     return timeA.compareTo(timeB);
                  });

                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: filteredDocs.length,
                    itemBuilder: (context, index) {
                      final doc = filteredDocs[index];
                      final data = doc.data() as Map<String, dynamic>;
                      final String dateStr = data['date'] ?? 'Unknown Date';
                      final String timeStr = data['departure_time'] ?? '00:00';
                      final int capacity = data['capacity'] ?? 13;
                      final int booked = data['booked_count'] ?? 0;
                      final int available = capacity - booked;
                      final bool isFull = available <= 0;

                      String displayDate = dateStr;
                      try {
                        final dt = DateTime.parse(dateStr);
                        displayDate = DateFormat('EEE, dd MMM yyyy').format(dt);
                      } catch (_) {}

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          leading: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.calendar_today, color: isFull ? Colors.grey : const Color(0xFF104C97)),
                            ],
                          ),
                          title: Text(
                            timeStr, 
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)
                          ),
                          subtitle: Text(displayDate),
                          trailing: SizedBox(
                            width: 100,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  isFull ? "FULL" : "$available left",
                                  style: TextStyle(
                                    color: isFull ? Colors.red : Colors.green,
                                    fontWeight: FontWeight.bold
                                  ),
                                ),
                                const SizedBox(height: 4),
                                SizedBox(
                                  height: 30,
                                  child: ElevatedButton(
                                    onPressed: isFull ? null : () => _bookRide(doc),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF104C97),
                                      foregroundColor: Colors.white,
                                      padding: EdgeInsets.zero,
                                    ),
                                    child: const Text("Book", style: TextStyle(fontSize: 12)),
                                  ),
                                ),
                              ],
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
  }
}