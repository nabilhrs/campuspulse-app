import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:campuspulse/modules/booking/booking_page.dart';
import 'package:campuspulse/modules/rating/rating_page.dart';

class MyBookingsPage extends StatefulWidget {
  const MyBookingsPage({super.key});

  @override
  State<MyBookingsPage> createState() => _MyBookingsPageState();
}

class _MyBookingsPageState extends State<MyBookingsPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final User? user = FirebaseAuth.instance.currentUser;
  
  final Map<String, String> _zoneNames = {};
  
  DateTimeRange? _selectedDateRange;
  String _selectedTypeFilter = 'all'; 

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

  Future<void> _loadZoneNames() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('Zones').get();
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final zoneId = data['zone_id'] ?? doc.id;
        final name = data['name'] ?? 'Unknown Zone';
        _zoneNames[zoneId] = name;
      }
      if (mounted) setState(() {}); 
    } catch (e) {
      debugPrint("Error loading zone names: $e");
    }
  }

  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return "N/A";
    if (timestamp is Timestamp) {
      return DateFormat('EEE, MMM d • hh:mm a').format(timestamp.toDate());
    }
    return timestamp.toString();
  }

  String _getFormattedDisplayTime(Map<String, dynamic> data) {
    if (data['date'] != null && data['departure_time'] != null) {
      try {
        final datePart = DateTime.parse(data['date']);
        final timeParts = data['departure_time'].toString().split(':');
        final int hour = int.parse(timeParts[0]);
        final int minute = int.parse(timeParts[1]);
        final fullDt = DateTime(datePart.year, datePart.month, datePart.day, hour, minute);
        return DateFormat('EEE, MMM d • hh:mm a').format(fullDt);
      } catch (e) {
        return "${data['date']} • ${data['departure_time']}";
      }
    }
    if (data['request_time'] != null && data['request_time'] is Timestamp) {
      return _formatDate(data['request_time']);
    }
    if (data['booking_time'] != null && data['booking_time'] is Timestamp) {
      return _formatDate(data['booking_time']);
    }
    return "Date N/A";
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'confirmed': return Colors.green;
      case 'pending': 
      case 'searching': return Colors.orange;
      case 'arriving': return Colors.blue;
      case 'on_board': 
      case 'onboard': return const Color(0xFF104C97);
      case 'completed': return Colors.teal;
      case 'cancelled': 
      case 'expired':
      case 'missed': return Colors.redAccent; 
      default: return Colors.grey;
    }
  }
  
  void _clearAllFilters() {
    setState(() {
      _selectedDateRange = null;
      _selectedTypeFilter = 'all';
    });
  }

  void _showFilterMenu() {
    DateTimeRange? tempDateRange = _selectedDateRange;
    String tempTypeFilter = _selectedTypeFilter;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Filter Bookings", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF104C97), letterSpacing: -0.5)),
                      TextButton(
                        onPressed: () {
                          setModalState(() {
                            tempDateRange = null;
                            tempTypeFilter = 'all';
                          });
                        },
                        child: const Text("Reset", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                      )
                    ],
                  ),
                  const SizedBox(height: 24),

                  const Text("Service Type", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _buildFilterTypeButton("All", 'all', tempTypeFilter, (val) => setModalState(() => tempTypeFilter = val)),
                      const SizedBox(width: 10),
                      _buildFilterTypeButton("Peak Hour", 'scheduled', tempTypeFilter, (val) => setModalState(() => tempTypeFilter = val)),
                      const SizedBox(width: 10),
                      _buildFilterTypeButton("On-Demand", 'ondemand', tempTypeFilter, (val) => setModalState(() => tempTypeFilter = val)),
                    ],
                  ),
                  
                  const SizedBox(height: 32),

                  const Text("Date Range", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: () async {
                      final DateTimeRange? newRange = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime(2024),
                        lastDate: DateTime(2030),
                        initialDateRange: tempDateRange,
                        builder: (context, child) => Theme(
                          data: Theme.of(context).copyWith(
                            colorScheme: const ColorScheme.light(primary: Color(0xFF104C97), onPrimary: Colors.white, onSurface: Colors.black),
                          ),
                          child: child!,
                        ),
                      );
                      if (newRange != null) {
                        setModalState(() => tempDateRange = newRange);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.calendar_month_rounded, color: tempDateRange == null ? Colors.grey : const Color(0xFF104C97)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              tempDateRange == null 
                                  ? "Any Date" 
                                  : "${DateFormat('MMM d, yyyy').format(tempDateRange!.start)} - ${DateFormat('MMM d, yyyy').format(tempDateRange!.end)}",
                              style: TextStyle(
                                color: tempDateRange == null ? Colors.grey.shade600 : Colors.black87,
                                fontWeight: tempDateRange == null ? FontWeight.normal : FontWeight.bold,
                                fontSize: 15
                              ),
                            ),
                          ),
                          if (tempDateRange != null)
                            GestureDetector(
                              onTap: () => setModalState(() => tempDateRange = null),
                              child: const Icon(Icons.close, color: Colors.grey, size: 20),
                            )
                          else
                            const Icon(Icons.chevron_right, color: Colors.grey),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 40),

                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _selectedDateRange = tempDateRange;
                          _selectedTypeFilter = tempTypeFilter;
                        });
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF104C97),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                      child: const Text("Apply Filters", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  )
                ],
              ),
            );
          }
        );
      }
    );
  }

  Widget _buildFilterTypeButton(String label, String value, String currentValue, Function(String) onTap) {
    bool isSelected = value == currentValue;
    return Expanded(
      child: GestureDetector(
        onTap: () => onTap(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF104C97) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isSelected ? const Color(0xFF104C97) : Colors.grey.shade300),
            boxShadow: isSelected ? [BoxShadow(color: const Color(0xFF104C97).withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))] : [],
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(color: isSelected ? Colors.white : Colors.grey.shade700, fontWeight: isSelected ? FontWeight.bold : FontWeight.w600, fontSize: 13),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActiveFiltersRow() {
    if (_selectedDateRange == null && _selectedTypeFilter == 'all') {
      return const SizedBox.shrink(); 
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(left: 24, right: 24, bottom: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: [
            const Icon(Icons.filter_list, size: 18, color: Colors.grey),
            const SizedBox(width: 12),
            
            if (_selectedTypeFilter != 'all')
              _buildActiveChip(
                icon: Icons.directions_bus,
                label: _selectedTypeFilter == 'scheduled' ? "Peak Hour" : "On-Demand",
                onClear: () => setState(() => _selectedTypeFilter = 'all'),
              ),
              
            if (_selectedDateRange != null)
              _buildActiveChip(
                icon: Icons.calendar_month,
                label: "${DateFormat('MMM d').format(_selectedDateRange!.start)} - ${DateFormat('MMM d').format(_selectedDateRange!.end)}",
                onClear: () => setState(() => _selectedDateRange = null),
              ),

            TextButton(
              onPressed: _clearAllFilters,
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12)),
              child: const Text("Clear All", style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold)),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildActiveChip({required IconData icon, required String label, required VoidCallback onClear}) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF0AB00).withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF0AB00).withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFFE69B00)),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: Color(0xFFE69B00), fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onClear,
            child: const Icon(Icons.close, size: 14, color: Color(0xFFE69B00)),
          )
        ],
      ),
    );
  }

  void _showBookingDetails(Map<String, dynamic> data, String bookingId) {
    String zoneDisplay = "Unknown Zone";
    if (data['zone_id'] != null) {
      zoneDisplay = _zoneNames[data['zone_id']] ?? data['zone_id'];
    } else if (data['zone'] != null) {
      zoneDisplay = data['zone'];
    }
    
    final double fare = double.tryParse(data['fare']?.toString() ?? '0.0') ?? 0.0;
    final isScheduled = data['type'] == 'scheduled';

    DateTime? tripDt;
    if (data['date'] != null && data['departure_time'] != null) {
      try {
        final parts = data['departure_time'].toString().split(':');
        final datePart = DateTime.parse(data['date']);
        tripDt = DateTime(datePart.year, datePart.month, datePart.day, int.parse(parts[0]), int.parse(parts[1]));
      } catch (_) {}
    }
    if (tripDt == null && data['request_time'] != null && data['request_time'] is Timestamp) {
      tripDt = (data['request_time'] as Timestamp).toDate();
    }
    if (tripDt == null && data['booking_time'] != null && data['booking_time'] is Timestamp) {
      tripDt = (data['booking_time'] as Timestamp).toDate();
    }
    
    String displayDate = tripDt != null ? DateFormat('dd MMM yyyy').format(tripDt) : 'N/A';
    String displayTime = tripDt != null ? DateFormat('hh:mm a').format(tripDt) : 'N/A';
    if (isScheduled && data['departure_time'] != null) {
      displayTime = data['departure_time'];
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
            elevation: 20,
            borderRadius: const BorderRadius.only(topLeft: Radius.circular(32), bottomLeft: Radius.circular(32)),
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
                      const Text("Trip Details", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF104C97), letterSpacing: -0.5)),
                      Container(
                        decoration: BoxDecoration(color: Colors.grey.shade100, shape: BoxShape.circle),
                        child: IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded, color: Colors.grey, size: 20),
                        ),
                      )
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text("ID: #${bookingId.toUpperCase()}", style: const TextStyle(fontFamily: 'Courier', fontSize: 13, color: Colors.grey, fontWeight: FontWeight.bold)),
                  const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Divider(height: 1)),

                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        children: [
                          _buildDetailBox("Status", (data['status'] ?? 'Unknown').toString().toUpperCase(), valueColor: _getStatusColor(data['status'] ?? '')),
                          _buildDetailBox("Service Type", (data['type'] ?? 'Unknown').toString().toUpperCase()),
                          _buildDetailBox("Zone", zoneDisplay),
                          
                          const SizedBox(height: 16),
                          if (isScheduled && (data['route_name'] != null || data['route_id'] != null)) 
                            _buildDetailBox("Route", data['route_name'] ?? data['route_id'] ?? 'N/A'),
                          
                          if (data['pickup_stop_name'] != null || data['pickup_stop_id'] != null || data['pickup_location'] != null)
                            _buildDetailBox("Pickup", data['pickup_stop_name'] ?? data['pickup_stop_id'] ?? data['pickup_location'] ?? 'N/A'),
                          
                          if (data['dropoff_stop_name'] != null || data['dropoff_stop_id'] != null || data['dropoff_location'] != null)
                            _buildDetailBox("Dropoff", data['dropoff_stop_name'] ?? data['dropoff_stop_id'] ?? data['dropoff_location'] ?? 'N/A')
                          else if (data['destination'] != null)
                            _buildDetailBox("Destination", data['destination']),

                          const SizedBox(height: 16),
                          _buildDetailBox("Date", displayDate),
                          _buildDetailBox("Time", displayTime),
                          
                          const SizedBox(height: 16),
                          
                          FutureBuilder<DocumentSnapshot>(
                            future: data['driver_id'] != null && data['driver_id'] != 'TBD' && data['driver_id'].toString().trim().isNotEmpty 
                                ? FirebaseFirestore.instance.collection('Staffs').doc(data['driver_id']).get() 
                                : null,
                            builder: (context, snap) {
                              String sId = data['shuttle_id'] ?? 'Not Assigned';
                              if (sId.isEmpty || sId == 'TBD') sId = 'Not Assigned';
                              
                              String dName = data['driver_name']?.toString().split(' ').first ?? 'Not Assigned';
                              if (dName.isEmpty || dName == 'TBD') dName = 'Not Assigned';

                              if (snap.hasData && snap.data!.exists) {
                                final staffData = snap.data!.data() as Map<String, dynamic>;
                                dName = staffData['full_name'] ?? dName; 
                                if (sId == 'Not Assigned') sId = staffData['assigned_shuttle_id'] ?? 'Not Assigned';
                              }

                              return Column(
                                children: [
                                  _buildDetailBox("Shuttle ID", sId),
                                  _buildDetailBox("Driver", dName),
                                ],
                              );
                            }
                          ),
                          
                          const SizedBox(height: 16),
                          _buildDetailBox("Fare Paid", "RM ${fare.toStringAsFixed(2)}", valueColor: Colors.black),
                        ],
                      ),
                    ),
                  ),

                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF104C97),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                      child: const Text("Done", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  )
                ],
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        var tween = Tween(begin: const Offset(1.0, 0.0), end: Offset.zero).chain(CurveTween(curve: Curves.easeOutQuint));
        return SlideTransition(position: animation.drive(tween), child: child);
      },
    );
  }

  Widget _buildDetailBox(String label, String value, {Color? valueColor}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 100, child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w600))),
          Expanded(child: Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: valueColor ?? Colors.black87), textAlign: TextAlign.right)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8F9FA),
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF104C97)),
        centerTitle: true,
        title: const Text("My Bookings", style: TextStyle(color: Color(0xFF104C97), fontWeight: FontWeight.w900, letterSpacing: -0.5)),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
              color: _selectedDateRange != null || _selectedTypeFilter != 'all' 
                  ? const Color(0xFF104C97).withOpacity(0.1) 
                  : Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: IconButton(
              icon: Icon(Icons.filter_list_rounded, color: const Color(0xFF104C97), size: 22),
              onPressed: _showFilterMenu,
              tooltip: "Filter & Sort",
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(70),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(25),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 15, offset: const Offset(0, 5))],
            ),
            child: TabBar(
              controller: _tabController,
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              indicator: BoxDecoration(
                borderRadius: BorderRadius.circular(25),
                color: const Color(0xFF104C97),
                boxShadow: [BoxShadow(color: const Color(0xFF104C97).withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))],
              ),
              labelColor: Colors.white,
              unselectedLabelColor: Colors.grey.shade500,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              tabs: const [Tab(text: "Upcoming"), Tab(text: "History")],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          _buildActiveFiltersRow(),
            
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('Bookings')
                  .where('user_id', isEqualTo: user?.uid)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) return Center(child: Text("Error: ${snapshot.error}", style: const TextStyle(color: Colors.red)));
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Color(0xFF104C97)));

                var allDocs = snapshot.data!.docs;
                
                allDocs.sort((a, b) {
                  final dataA = a.data() as Map<String, dynamic>;
                  final dataB = b.data() as Map<String, dynamic>;
                  
                  DateTime getTime(Map<String, dynamic> data) {
                    if (data['booking_time'] != null && data['booking_time'] is Timestamp) {
                      return (data['booking_time'] as Timestamp).toDate();
                    }
                    if (data['request_time'] != null && data['request_time'] is Timestamp) {
                      return (data['request_time'] as Timestamp).toDate();
                    }
                    return DateTime.now(); 
                  }

                  return getTime(dataB).compareTo(getTime(dataA));
                });
                
                if (_selectedTypeFilter != 'all') {
                  allDocs = allDocs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return (data['type'] ?? 'unknown') == _selectedTypeFilter;
                  }).toList();
                }

                if (_selectedDateRange != null) {
                  allDocs = allDocs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    DateTime? tripDate;

                    if (data['date'] != null) {
                      try { tripDate = DateTime.parse(data['date']); } catch (_) {}
                    }
                    if (tripDate == null && data['request_time'] != null && data['request_time'] is Timestamp) {
                      tripDate = (data['request_time'] as Timestamp).toDate();
                    }
                    if (tripDate == null && data['booking_time'] != null && data['booking_time'] is Timestamp) {
                      tripDate = (data['booking_time'] as Timestamp).toDate();
                    }

                    if (tripDate == null) return false;
                    
                    final start = _selectedDateRange!.start;
                    final end = _selectedDateRange!.end.add(const Duration(days: 1));
                    return tripDate.isAfter(start.subtract(const Duration(seconds: 1))) && tripDate.isBefore(end);
                  }).toList();
                }

                final upcoming = allDocs.where((doc) {
                  final status = (doc.data() as Map)['status'] ?? 'unknown';
                  return ['confirmed', 'pending', 'searching', 'arriving', 'on_board', 'onboard'].contains(status);
                }).toList();

                // --- THE FIX: Included 'missed' status correctly in History view ---
                final history = allDocs.where((doc) {
                  final status = (doc.data() as Map)['status'] ?? 'unknown';
                  return ['completed', 'cancelled', 'expired', 'missed'].contains(status);
                }).toList();

                return TabBarView(
                  controller: _tabController,
                  physics: const BouncingScrollPhysics(),
                  children: [
                    _buildBookingList(upcoming, isEmptyMessage: "No upcoming trips found.", icon: Icons.event_available),
                    _buildBookingList(history, isEmptyMessage: "No ride history found.", icon: Icons.history_rounded),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBookingList(List<QueryDocumentSnapshot> docs, {required String isEmptyMessage, required IconData icon}) {
    if (docs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20)]),
              child: Icon(icon, size: 50, color: Colors.grey.shade400),
            ),
            const SizedBox(height: 20),
            Text(isEmptyMessage, style: TextStyle(color: Colors.grey.shade600, fontSize: 16, fontWeight: FontWeight.w600)),
            if (_selectedDateRange != null || _selectedTypeFilter != 'all')
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text("Try adjusting your filters.", style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
              )
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(24),
      physics: const BouncingScrollPhysics(),
      itemCount: docs.length,
      itemBuilder: (context, index) {
        final data = docs[index].data() as Map<String, dynamic>;
        final String type = data['type'] ?? 'Unknown';
        final String status = data['status'] ?? 'Unknown';
        final bookingId = docs[index].id;
        final bool isRated = data['is_rated'] == true;
        final String driverId = data['driver_id'] ?? 'TBD';
        
        String formattedTime = _getFormattedDisplayTime(data);
        String zoneDisplay = data['zone_id'] != null ? (_zoneNames[data['zone_id']] ?? "Zone ${data['zone_id']}") : "Unknown Zone";
        String primaryLocation = data['route_name'] ?? data['dropoff_stop_name'] ?? data['destination'] ?? "Trip to Destination";

        return GestureDetector(
          onTap: () => _showBookingDetails(data, bookingId),
          child: Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.grey.shade100),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))]
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(color: _getStatusColor(status).withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.lens, size: 8, color: _getStatusColor(status)),
                          const SizedBox(width: 6),
                          Text(status.toUpperCase(), style: TextStyle(color: _getStatusColor(status), fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 0.5)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                      child: Text(type == 'scheduled' ? 'Scheduled' : 'On-Demand', style: TextStyle(color: Colors.grey.shade600, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.blue.shade50, shape: BoxShape.circle),
                      child: Icon(type == 'scheduled' ? Icons.calendar_month_rounded : Icons.access_time_rounded, color: const Color(0xFF104C97), size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(formattedTime, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.black87), overflow: TextOverflow.ellipsis)),
                  ],
                ),
                const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1)),
                
                Row(
                  children: [
                    const Icon(Icons.route_rounded, color: Colors.grey, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(primaryLocation, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14), overflow: TextOverflow.ellipsis),
                          Text(zoneDisplay, style: TextStyle(color: Colors.grey.shade500, fontSize: 11, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios_rounded, color: Colors.grey, size: 14),
                  ],
                ),
                  
                if (['confirmed', 'pending', 'searching'].contains(status))
                  Padding(
                    padding: const EdgeInsets.only(top: 16.0),
                    child: SizedBox(
                      width: double.infinity,
                      height: 45,
                      child: OutlinedButton(
                        onPressed: () => _cancelBooking(docs[index]),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          side: BorderSide(color: Colors.redAccent.shade100, width: 1.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text("Cancel Ride", style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  )
                else ...[
                  // RATE DRIVER BUTTON
                  if (status == 'completed' && !isRated && driverId != 'TBD')
                    Padding(
                      padding: const EdgeInsets.only(top: 16.0),
                      child: SizedBox(
                        width: double.infinity,
                        height: 45,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => RatingPage(bookingId: bookingId, driverId: driverId),
                              ),
                            );
                          },
                          icon: const Icon(Icons.star_rate_rounded, size: 18),
                          label: const Text("Rate Driver", style: TextStyle(fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFF0AB00), 
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                        ),
                      ),
                    )
                  else if (status == 'completed' && isRated)
                    Padding(
                      padding: const EdgeInsets.only(top: 16.0),
                      child: Row(
                         children: [
                            const Icon(Icons.check_circle, color: Colors.green, size: 16),
                            const SizedBox(width: 8),
                            const Text("You rated this trip", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12))
                         ]
                      )
                    ),
                    
                  // REBOOK RIDE BUTTON
                  if (['completed', 'cancelled', 'expired', 'missed'].contains(status) && type == 'ondemand')
                    Padding(
                      padding: const EdgeInsets.only(top: 12.0),
                      child: SizedBox(
                        width: double.infinity,
                        height: 45,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            final result = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => BookingPage(
                                  zoneId: data['zone_id'] ?? '',
                                  zoneName: zoneDisplay,
                                  initialIndex: 1, 
                                  initialPickupStopId: data['pickup_stop_id'],
                                  initialPickupStopName: data['pickup_stop_name'],
                                  initialDropoffStopId: data['dropoff_stop_id'],
                                  initialDropoffStopName: data['dropoff_stop_name'],
                                )
                              )
                            );
                            if (result == 'goToTracking' && mounted) {
                              Navigator.pop(context, 'goToTracking');
                            }
                          },
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text("Rebook Ride", style: TextStyle(fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF104C97),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                        ),
                      ),
                    ),
                ]
              ],
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Cancel Ride?", style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text("Are you sure you want to cancel this booking? Your fare will be refunded."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("No", style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true), 
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: const Text("Yes, Cancel")
          ),
        ],
      )
    ) ?? false;

    if (!confirm) return;

    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final freshDoc = await tx.get(doc.reference);
        final data = freshDoc.data() as Map<String, dynamic>;
        
        if (data['status'] == 'cancelled') throw Exception("Booking is already cancelled.");
        
        final studentRef = FirebaseFirestore.instance.collection('Students').doc(user!.uid);
        final studentSnap = await tx.get(studentRef);
        
        DocumentSnapshot? scheduleSnap;
        final isScheduled = data['type'] == 'scheduled';
        if (isScheduled && data['schedule_id'] != null) {
          final scheduleRef = FirebaseFirestore.instance.collection('Schedules').doc(data['schedule_id']);
          scheduleSnap = await tx.get(scheduleRef);
        }

        final fare = double.tryParse(data['fare']?.toString() ?? '2.0') ?? 2.0;

        tx.update(doc.reference, {'status': 'cancelled'});

        if (studentSnap.exists) {
          final currentBalance = (studentSnap.data()?['balance'] ?? 0.0).toDouble();
          tx.update(studentRef, {'balance': currentBalance + fare});
        }

        if (scheduleSnap != null && scheduleSnap.exists) {
          final int bookedCount = (scheduleSnap.data() as Map<String, dynamic>?)?['booked_count'] ?? 1;
          tx.update(scheduleSnap.reference, {'booked_count': (bookedCount - 1).clamp(0, 999)});
        }

        final txnRef = FirebaseFirestore.instance.collection('Transactions').doc();
        tx.set(txnRef, {
          'user_id': user!.uid,
          'type': 'credit',
          'amount': fare,
          'description': 'Refund: Cancelled Trip',
          'reference_id': doc.id,
          'timestamp': FieldValue.serverTimestamp(),
        });
      });

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text("Booking cancelled. Fare refunded."), backgroundColor: Colors.green, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), margin: const EdgeInsets.all(20)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Cancellation failed: $e"), backgroundColor: Colors.red));
    }
  }
}