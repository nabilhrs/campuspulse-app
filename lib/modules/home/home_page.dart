import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:campuspulse/modules/home/zone_picker.dart';
import 'package:campuspulse/modules/home/profile_page.dart'; 
import 'package:campuspulse/modules/booking/booking_page.dart';
import 'package:campuspulse/modules/recommendation/recommendation_page.dart';
import 'package:campuspulse/modules/tracking/tracking_page.dart';
import 'package:intl/intl.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;
  
  String? selectedZoneId;
  String? selectedZoneName;
  
  final User? user = FirebaseAuth.instance.currentUser;
  String displayName = "Student"; 

  @override
  void initState() {
    super.initState();
    _fetchUserData();
  }

  Future<void> _fetchUserData() async {
    if (user != null) {
      try {
        final doc = await FirebaseFirestore.instance.collection('Students').doc(user!.uid).get();
        if (doc.exists && mounted) {
          final data = doc.data();
          setState(() {
            String? username = data?['username'];
            String? fullName = data?['full_name'];

            if (username != null && username.isNotEmpty) {
              displayName = username;
            } else if (fullName != null && fullName.isNotEmpty) {
              displayName = fullName.split(' ').first;
            } else {
              displayName = 'Student';
            }
          });
        }
      } catch (e) {
        debugPrint("Error fetching data: $e");
      }
    }
  }

  String _getTimeBasedGreeting() {
    var hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  Future<void> _confirmLogout() async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Confirm Logout"),
        content: const Text("Are you sure you want to log out of CampusPulse?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context); 
              await FirebaseAuth.instance.signOut();
              if (mounted) Navigator.pushReplacementNamed(context, '/login');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF104C97),
              foregroundColor: Colors.white,
            ),
            child: const Text("Logout"),
          ),
        ],
      ),
    );
  }

  // --- NEW: Show Announcement Details Dialog ---
  void _showAnnouncementDetails(String title, String message, dynamic dateData) {
    String dateStr = "";
    if (dateData is Timestamp) {
      dateStr = DateFormat('dd MMM yyyy, hh:mm a').format(dateData.toDate());
    } else if (dateData is String) {
      dateStr = dateData;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.notifications_active, color: Color(0xFF104C97)),
            const SizedBox(width: 10),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (dateStr.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    dateStr,
                    style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ),
              Text(
                message,
                style: const TextStyle(fontSize: 15, height: 1.5, color: Colors.black87),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }

  void _onItemTapped(int index) {
    setState(() => _currentIndex = index);
  }

  void _handleZoneSelection(String zoneId, String zoneName) {
    setState(() {
      selectedZoneId = zoneId;
      selectedZoneName = zoneName;
    });
  }

  void _resetZone() {
    setState(() {
      selectedZoneId = null;
      selectedZoneName = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      _buildHomeTab(),           
      const TrackingPage(), 
      const ProfilePage(),  
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF104C97),
        elevation: 0,
        title: Row(
          children: [
            const Icon(Icons.directions_bus_filled, color: Colors.white),
            const SizedBox(width: 10),
            const Text("CampusPulse", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        automaticallyImplyLeading: false, 
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: _confirmLogout, 
          )
        ],
      ),
      body: pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: _onItemTapped,
        selectedItemColor: const Color(0xFF104C97),
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: "Home"),
          BottomNavigationBarItem(icon: Icon(Icons.map_rounded), label: "Tracking"),
          BottomNavigationBarItem(icon: Icon(Icons.person_rounded), label: "Profile"),
        ],
      ),
    );
  }

  Widget _buildHomeTab() {
    if (selectedZoneId == null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _getTimeBasedGreeting(),
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),
            Text(
              displayName, 
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF104C97)),
            ),
            const SizedBox(height: 30),
            ZonePicker(onZoneSelected: _handleZoneSelection),
          ],
        ),
      );
    }
    return _buildDashboard();
  }

  Widget _buildDashboard() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- Dynamic Header ---
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_getTimeBasedGreeting(), style: const TextStyle(fontSize: 14, color: Colors.grey)),
                  Text(
                    displayName,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.green.withOpacity(0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.circle, size: 10, color: Colors.green),
                    SizedBox(width: 6),
                    Text("Service Normal", style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
              )
            ],
          ),
          
          const SizedBox(height: 20),

          // --- Location Context ---
          Row(
            children: [
              const Icon(Icons.location_on, size: 16, color: Color(0xFF104C97)),
              const SizedBox(width: 4),
              Text("Current Zone: ", style: TextStyle(color: Colors.grey[600])),
              Text(
                selectedZoneName!,
                style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF104C97)),
              ),
              const Spacer(),
              TextButton(
                onPressed: _resetZone, 
                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(50, 30), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                child: const Text("Change", style: TextStyle(fontSize: 12)),
              )
            ],
          ),

          const SizedBox(height: 10),
          
          // --- DYNAMIC HERO SECTION ---
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('Bookings')
                .where('user_id', isEqualTo: user?.uid)
                .where('status', whereIn: ['confirmed', 'pending', 'arriving'])
                .orderBy('booking_time', descending: true)
                .limit(1)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return _buildBookNowBanner(); 
              }
              if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
                final booking = snapshot.data!.docs.first;
                return _buildActiveRideCard(booking);
              }
              return _buildBookNowBanner();
            },
          ),

          const SizedBox(height: 25),

          // --- Smart Planner Card ---
          InkWell(
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => RecommendationPage(zoneId: selectedZoneId!, zoneName: selectedZoneName!)));
            },
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.purple.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.purple.shade100, width: 1.5),
                boxShadow: [
                  BoxShadow(color: Colors.purple.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.purple.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.auto_awesome, color: Colors.purple),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Smart Trip Planner", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        SizedBox(height: 4),
                        Text("Get smart ride recommendations based on your class schedule.", style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.grey),
                ],
              ),
            ),
          ),

          const SizedBox(height: 25),
          
          // --- Quick Actions Grid ---
          const Text("Quick Actions", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 15),
          Row(
            children: [
              _buildActionCard(
                Icons.calendar_month, "Schedule", Colors.blue.shade50, Colors.blue.shade700,
                () => Navigator.push(context, MaterialPageRoute(builder: (context) => BookingPage(zoneId: selectedZoneId!, zoneName: selectedZoneName!, initialIndex: 0))),
              ),
              const SizedBox(width: 15),
              _buildActionCard(
                Icons.directions_car, "On-Demand", Colors.orange.shade50, Colors.orange.shade800,
                () => Navigator.push(context, MaterialPageRoute(builder: (context) => BookingPage(zoneId: selectedZoneId!, zoneName: selectedZoneName!, initialIndex: 1))),
              ),
            ],
          ),

          const SizedBox(height: 30),
          
          // --- Real Service Updates ---
          const Text("Service Updates", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 15),
          
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('Announcements')
                // .where('status', isEqualTo: 'sent') // REMOVED to avoid Index Error
                .orderBy('created_at', descending: true)
                .limit(20) // Fetch slightly more to filter locally
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) return Text("Updates unavailable: ${snapshot.error}");
              if (!snapshot.hasData) return const Center(child: LinearProgressIndicator(minHeight: 2));
              
              // 1. Client-Side Filtering for Audience AND Status
              final docs = snapshot.data!.docs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                
                // Filter status here instead of in Query
                if (data['status'] != 'sent') return false;

                final audience = (data['target_audience'] ?? 'all').toString().toLowerCase();
                // Show if audience is 'all', 'student', or 'students'
                return audience == 'all' || audience.contains('student');
              }).take(3).toList(); // Take top 3 relevant ones

              if (docs.isEmpty) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12)),
                  child: const Text("No new announcements.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                );
              }

              return Column(
                children: docs.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: _buildNewsCard(
                      data['title'] ?? 'Notice', 
                      data['message'] ?? '', 
                      Icons.notifications_active, 
                      Colors.blue,
                      () => _showAnnouncementDetails(
                        data['title'] ?? 'Notice',
                        data['message'] ?? '',
                        data['created_at'],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
          
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // --- WIDGET: Default "Book Now" Banner ---
  Widget _buildBookNowBanner() {
    return Container(
      padding: const EdgeInsets.all(24),
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF104C97), Color(0xFF0D3B7A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF104C97).withOpacity(0.4),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Ready to go?", style: TextStyle(color: Colors.white70, fontSize: 14)),
                  SizedBox(height: 4),
                  Text("Book a Ride", style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.arrow_forward, color: Colors.white),
              )
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context, 
                  MaterialPageRoute(builder: (context) => BookingPage(zoneId: selectedZoneId!, zoneName: selectedZoneName!))
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF0AB00),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text("View Schedule", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          )
        ],
      ),
    );
  }

  // --- WIDGET: Active Ride Card ---
  Widget _buildActiveRideCard(DocumentSnapshot bookingDoc) {
    final data = bookingDoc.data() as Map<String, dynamic>;
    final status = data['status'] ?? 'Unknown';
    // Format Time
    String timeDisplay = "Now";
    if (data['departure_time'] != null) {
      timeDisplay = data['departure_time'];
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF104C97).withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.directions_bus, color: Color(0xFF104C97)),
                  const SizedBox(width: 8),
                  Text("Upcoming Trip", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[800], fontSize: 16)),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
                child: Text(status.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green.shade700)),
              )
            ],
          ),
          const Divider(height: 24),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Departure", style: TextStyle(fontSize: 12, color: Colors.grey)),
                    Text(timeDisplay, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text("Shuttle", style: TextStyle(fontSize: 12, color: Colors.grey)),
                    Text(data['shuttle_id'] ?? 'Assigning...', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                setState(() => _currentIndex = 1);
              },
              icon: const Icon(Icons.map, size: 18),
              label: const Text("Track Ride"),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF104C97),
                side: const BorderSide(color: Color(0xFF104C97)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildActionCard(IconData icon, String label, Color bgColor, Color iconColor, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 110,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: iconColor.withOpacity(0.1), blurRadius: 8)],
                ),
                child: Icon(icon, size: 28, color: iconColor),
              ),
              const SizedBox(height: 12),
              Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: iconColor.withOpacity(0.8))),
            ],
          ),
        ),
      ),
    );
  }

  // --- WIDGET: News Card with Tap ---
  Widget _buildNewsCard(String title, String description, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade100),
          boxShadow: [
            BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2))
          ]
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 4),
                  Text(description, style: const TextStyle(fontSize: 13, color: Colors.grey, height: 1.4), maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}