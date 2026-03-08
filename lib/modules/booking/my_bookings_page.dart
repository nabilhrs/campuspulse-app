import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class MyBookingsPage extends StatefulWidget {
  const MyBookingsPage({super.key});

  @override
  State<MyBookingsPage> createState() => _MyBookingsPageState();
}

class _MyBookingsPageState extends State<MyBookingsPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final User? user = FirebaseAuth.instance.currentUser;
  
  // Cache for Zone Names: { "ZONE001": "Bangsar" }
  final Map<String, String> _zoneNames = {};
  
  // Date Range Filter State
  DateTimeRange? _selectedDateRange;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadZoneNames();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // --- Helper: Load Zone Names ---
  Future<void> _loadZoneNames() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('Zones').get();
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final zoneId = data['zone_id'] ?? doc.id;
        final name = data['name'] ?? 'Unknown Zone';
        _zoneNames[zoneId] = name;
      }
      if (mounted) setState(() {}); // Refresh UI once loaded
    } catch (e) {
      debugPrint("Error loading zone names: $e");
    }
  }

  // Helper for generic timestamps (used in details view)
  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return "N/A";
    if (timestamp is Timestamp) {
      return DateFormat('EEE, MMM d • hh:mm a').format(timestamp.toDate());
    }
    return timestamp.toString();
  }

  // --- NEW: Intelligent Date/Time Formatter for List Cards ---
  String _getFormattedDisplayTime(Map<String, dynamic> data) {
    // 1. Scheduled Ride: Has separate 'date' (String) and 'departure_time' (String)
    if (data['date'] != null && data['departure_time'] != null) {
      try {
        // Parse "2025-12-29"
        final datePart = DateTime.parse(data['date']);
        
        // Parse "06:30" (Assuming HH:mm 24-hour format from DB)
        final timeParts = data['departure_time'].toString().split(':');
        final int hour = int.parse(timeParts[0]);
        final int minute = int.parse(timeParts[1]);

        // Combine into one DateTime
        final fullDt = DateTime(datePart.year, datePart.month, datePart.day, hour, minute);
        
        // Format to "Fri, Jan 9 • 06:30 AM"
        return DateFormat('EEE, MMM d • hh:mm a').format(fullDt);
      } catch (e) {
        // Fallback if parsing fails: "2025-12-29 • 06:30"
        return "${data['date']} • ${data['departure_time']}";
      }
    }
    
    // 2. On-Demand Ride: Uses 'request_time' (Timestamp)
    if (data['request_time'] != null && data['request_time'] is Timestamp) {
      return _formatDate(data['request_time']);
    }

    // 3. Fallback to creation time
    if (data['booking_time'] != null && data['booking_time'] is Timestamp) {
      return _formatDate(data['booking_time']);
    }

    return "Date N/A";
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'confirmed': return Colors.green;
      case 'pending': return Colors.orange;
      case 'arriving': return Colors.blue;
      case 'on_board': return const Color(0xFF104C97);
      case 'completed': return Colors.green;
      case 'cancelled': return Colors.red;
      default: return Colors.black;
    }
  }

  // --- Date Range Picker ---
  Future<void> _pickDateRange() async {
    final DateTimeRange? newRange = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
      initialDateRange: _selectedDateRange,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF104C97),
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (newRange != null) {
      setState(() {
        _selectedDateRange = newRange;
      });
    }
  }

  void _clearFilter() {
    setState(() {
      _selectedDateRange = null;
    });
  }

  // --- SIDE SHEET ANIMATION ---
  void _showBookingDetails(Map<String, dynamic> data, String bookingId) {
    String zoneDisplay = "Unknown Zone";
    if (data['zone_id'] != null) {
      zoneDisplay = _zoneNames[data['zone_id']] ?? data['zone_id'];
    } else if (data['zone'] != null) {
      zoneDisplay = data['zone'];
    }

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: "Close",
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: Colors.white,
            elevation: 10,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              bottomLeft: Radius.circular(20),
            ),
            child: Container(
              width: MediaQuery.of(context).size.width * 0.85,
              height: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Trip Details",
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF104C97)),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded, color: Colors.grey),
                      )
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text("ID: #$bookingId", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  const Divider(height: 40),

                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          _buildDetailItem("Service Type", (data['type'] ?? 'Unknown').toString().toUpperCase()),
                          _buildDetailItem("Status", (data['status'] ?? 'Unknown').toString().toUpperCase()),
                          _buildDetailItem("Zone", zoneDisplay),
                          
                          const SizedBox(height: 10),
                          if (data['route_name'] != null)
                            _buildDetailItem("Route", data['route_name']),
                          
                          if (data['pickup_stop_id'] != null)
                            _buildDetailItem("Pickup ID", data['pickup_stop_id']),
                          
                          if (data['dropoff_stop_id'] != null)
                            _buildDetailItem("Dropoff ID", data['dropoff_stop_id'])
                          else if (data['destination'] != null)
                            _buildDetailItem("Destination", data['destination']),

                          const SizedBox(height: 10),
                          if (data['date'] != null) _buildDetailItem("Date", data['date']),
                          if (data['departure_time'] != null) 
                            _buildDetailItem("Time", data['departure_time'])
                          else if (data['request_time'] != null) 
                            _buildDetailItem("Request Time", _formatDate(data['request_time'])),
                          
                          const SizedBox(height: 10),
                          if (data['shuttle_id'] != null) _buildDetailItem("Shuttle ID", data['shuttle_id']),
                          if (data['driver_name'] != null) _buildDetailItem("Driver", data['driver_name']),
                        ],
                      ),
                    ),
                  ),

                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF104C97),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text("Done"),
                    ),
                  )
                ],
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        const begin = Offset(1.0, 0.0);
        const end = Offset.zero;
        const curve = Curves.easeInOutCubic;
        var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
        return SlideTransition(
          position: animation.drive(tween),
          child: child,
        );
      },
    );
  }

  Widget _buildDetailItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 110, child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13))),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("My Bookings"),
        backgroundColor: const Color(0xFF104C97),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(_selectedDateRange == null ? Icons.filter_alt_outlined : Icons.filter_alt),
            onPressed: _pickDateRange,
            tooltip: "Filter by Date",
          ),
          if (_selectedDateRange != null)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: _clearFilter,
              tooltip: "Clear Filter",
            )
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFF0AB00),
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: "Upcoming"),
            Tab(text: "History"),
          ],
        ),
      ),
      body: Column(
        children: [
          // Filter Indicator
          if (_selectedDateRange != null)
            Container(
              width: double.infinity,
              color: Colors.grey.shade200,
              padding: const EdgeInsets.all(8),
              child: Text(
                "Filtering: ${DateFormat('MMM d').format(_selectedDateRange!.start)} - ${DateFormat('MMM d').format(_selectedDateRange!.end)}",
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black87, fontSize: 12),
              ),
            ),
            
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('Bookings')
                  .where('user_id', isEqualTo: user?.uid)
                  .orderBy('booking_time', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text("Error: ${snapshot.error}"));
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                var allDocs = snapshot.data!.docs;
                
                // --- Client-Side Date Filter (Updated Logic) ---
                if (_selectedDateRange != null) {
                  allDocs = allDocs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    
                    DateTime? tripDate;

                    // 1. Try to parse 'date' field (e.g., "2025-12-29") for Scheduled Rides
                    if (data['date'] != null) {
                      try {
                        tripDate = DateTime.parse(data['date']);
                      } catch (_) {}
                    }

                    // 2. Try 'request_time' for On-Demand Rides
                    if (tripDate == null && data['request_time'] != null && data['request_time'] is Timestamp) {
                      tripDate = (data['request_time'] as Timestamp).toDate();
                    }

                    // 3. Fallback to 'booking_time' if neither exists
                    if (tripDate == null && data['booking_time'] != null && data['booking_time'] is Timestamp) {
                      tripDate = (data['booking_time'] as Timestamp).toDate();
                    }

                    if (tripDate == null) return false;
                    
                    // Normalize comparison: Check if tripDate is within the selected range [start, end + 1 day)
                    final start = _selectedDateRange!.start;
                    final end = _selectedDateRange!.end.add(const Duration(days: 1));
                    
                    // Subtract/Add 1 second/tick is a common way to handle inclusive boundaries, 
                    // but 'isAfter' / 'isBefore' strictly requires > or <.
                    // Start is inclusive (>= start), End is inclusive for the day (< end + 1 day)
                    return tripDate.isAfter(start.subtract(const Duration(seconds: 1))) && 
                           tripDate.isBefore(end);
                  }).toList();
                }

                if (allDocs.isEmpty) {
                  return const Center(child: Text("No bookings found."));
                }

                final upcoming = allDocs.where((doc) {
                  final status = (doc.data() as Map)['status'] ?? 'unknown';
                  return ['confirmed', 'pending', 'arriving', 'on_board'].contains(status);
                }).toList();

                final history = allDocs.where((doc) {
                  final status = (doc.data() as Map)['status'] ?? 'unknown';
                  return ['completed', 'cancelled'].contains(status);
                }).toList();

                return TabBarView(
                  controller: _tabController,
                  children: [
                    _buildBookingList(upcoming, isEmptyMessage: "No upcoming trips."),
                    _buildBookingList(history, isEmptyMessage: "No booking history."),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBookingList(List<QueryDocumentSnapshot> docs, {required String isEmptyMessage}) {
    if (docs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.history, size: 60, color: Colors.grey),
            const SizedBox(height: 10),
            Text(isEmptyMessage, style: const TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: docs.length,
      itemBuilder: (context, index) {
        final data = docs[index].data() as Map<String, dynamic>;
        final String type = data['type'] ?? 'Unknown'; 
        final String status = data['status'] ?? 'Unknown';
        final bookingId = docs[index].id;
        
        // Use the new formatter here for list display
        String formattedTime = _getFormattedDisplayTime(data);
        
        // Resolve Zone Name for display
        String zoneDisplay = "Unknown Zone";
        if (data['zone_id'] != null) {
          zoneDisplay = _zoneNames[data['zone_id']] ?? "Zone ${data['zone_id']}";
        }

        return Card(
          elevation: 2,
          margin: const EdgeInsets.only(bottom: 12),
          child: InkWell(
            onTap: () => _showBookingDetails(data, bookingId),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _getStatusColor(status).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          status.toUpperCase(),
                          style: TextStyle(
                            color: _getStatusColor(status),
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Text(
                        type == 'scheduled' ? 'Scheduled' : 'On-Demand',
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        type == 'scheduled' ? Icons.calendar_month : Icons.access_time,
                        color: const Color(0xFF104C97),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      // Display the smart formatted date/time
                      Text(
                        formattedTime,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  
                  Text("Zone: $zoneDisplay", style: const TextStyle(color: Colors.black87)),
                  
                  if (data['destination'] != null)
                    Text("To: ${data['destination']}"),
                    
                  if (['confirmed', 'pending'].contains(status))
                    Padding(
                      padding: const EdgeInsets.only(top: 12.0),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () => _cancelBooking(docs[index]),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                          ),
                          child: const Text("Cancel Booking"),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _cancelBooking(DocumentSnapshot doc) async {
    bool confirm = await showDialog(
      context: context, 
      builder: (c) => AlertDialog(
        title: const Text("Cancel Ride?"),
        content: const Text("Are you sure you want to cancel this booking?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("No")),
          ElevatedButton(onPressed: () => Navigator.pop(c, true), child: const Text("Yes")),
        ],
      )
    ) ?? false;

    if (confirm) {
      try {
        await doc.reference.update({'status': 'cancelled'});
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Booking cancelled.")));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }
}