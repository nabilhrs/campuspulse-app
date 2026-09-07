import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:campuspulse/modules/home/zone_picker.dart';
import 'package:campuspulse/modules/home/profile_page.dart'; 
import 'package:campuspulse/modules/booking/booking_page.dart';
import 'package:campuspulse/modules/recommendation/recommendation_page.dart';
import 'package:campuspulse/modules/tracking/tracking_page.dart';
import 'package:campuspulse/modules/wallet/topup_page.dart';
import 'package:campuspulse/modules/notifications/notification_page.dart'; 
import 'package:campuspulse/data/services/location_service.dart';
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
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoDetectZone();
    });
  }

  // --- THE FIX: Added a dedicated refresh handler ---
  Future<void> _handleRefresh() async {
    await _fetchUserData();
    // Streams (Bookings, Announcements, etc.) update automatically, 
    // but this slight delay ensures the refresh spinner stays visible long enough for good UX
    await Future.delayed(const Duration(milliseconds: 800));
  }

  Future<void> _autoDetectZone() async {
    final locationService = LocationService();
    Map<String, dynamic>? detectedZone = await locationService.detectZone();
    
    if (detectedZone != null && mounted) {
      
      if (detectedZone['name'].toString().toLowerCase().contains('main campus')) {
        try {
          final kbSnap = await FirebaseFirestore.instance.collection('Zones')
              .where('name', isEqualTo: 'Kampung Baru')
              .limit(1)
              .get();
              
          if (kbSnap.docs.isNotEmpty) {
            detectedZone = {
              'zone_id': kbSnap.docs.first.id,
              'name': 'Kampung Baru',
            };
          }
        } catch (e) {
          debugPrint("Failed to remap Main Campus to Kampung Baru: $e");
        }
      }

      setState(() {
        selectedZoneId = detectedZone!['zone_id'];
        selectedZoneName = detectedZone['name'];
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.my_location, color: Colors.white, size: 20),
              const SizedBox(width: 12),
              Expanded(child: Text('Auto-detected Zone: ${detectedZone!['name']}', style: const TextStyle(fontWeight: FontWeight.w600))),
            ],
          ),
          backgroundColor: const Color(0xFF262562),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          margin: const EdgeInsets.only(bottom: 15, left: 20, right: 20),
          elevation: 8,
          duration: const Duration(seconds: 4),
        ),
      );
    }
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.blue.shade50, shape: BoxShape.circle),
              child: const Icon(Icons.campaign, color: Color(0xFF262562)),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
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
                    style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              Text(
                message,
                style: const TextStyle(fontSize: 15, height: 1.6, color: Colors.black87),
              ),
            ],
          ),
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF262562),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
              ),
              child: const Text("Close", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
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

  int _timeToMinutes(String timeStr) {
    try {
      timeStr = timeStr.trim().toUpperCase();
      bool isPM = timeStr.contains('PM');
      bool isAM = timeStr.contains('AM');
      timeStr = timeStr.replaceAll('AM', '').replaceAll('PM', '').trim();
      
      final parts = timeStr.split(':');
      if (parts.length != 2) return -1;
      
      int hour = int.parse(parts[0]);
      int minute = int.parse(parts[1]);
      
      if (isPM && hour != 12) hour += 12;
      if (isAM && hour == 12) hour = 0;
      
      return hour * 60 + minute;
    } catch (e) {
      return -1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      _buildHomeTab(),           
      const TrackingPage(), 
      const ProfilePage(),  
    ];

    return Scaffold(
      extendBody: true, 
      backgroundColor: const Color(0xFFF8F9FA), 
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: GestureDetector(
          onTap: () {
            if (_currentIndex != 0) {
              _onItemTapped(0);
            }
          },
          child: Image.asset(
            'assets/images/campuspulse_logo.png',
            height: 60, 
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: Color(0xFF262562),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.directions_bus_filled, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 10),
                  const Text("CampusPulse", style: TextStyle(color: Color(0xFF262562), fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                ],
              );
            },
          ),
        ),
        automaticallyImplyLeading: false, 
        actions: [
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('Notifications')
                .where('user_id', isEqualTo: user?.uid)
                .snapshots(),
            builder: (context, snapshot) {
              bool hasUnread = false;
              if (snapshot.hasData) {
                hasUnread = snapshot.data!.docs.any((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return data['is_read'] == false;
                });
              }

              return Container(
                margin: const EdgeInsets.only(right: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.notifications_none_rounded, color: Color(0xFF262562)),
                      onPressed: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationPage()));
                      },
                    ),
                    if (hasUnread)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: Colors.redAccent,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2), 
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          )
        ],
      ),
      body: pages[_currentIndex],
      bottomNavigationBar: _buildConvexNavBar(),
    );
  }

  Widget _buildConvexNavBar() {
    final screenWidth = MediaQuery.of(context).size.width;
    final itemWidth = screenWidth / 3;
    final targetX = (_currentIndex * itemWidth) + (itemWidth / 2);

    return SizedBox(
      height: 90, 
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: targetX, end: targetX),
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutQuint,
        builder: (context, x, child) {
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: NavBarPainter(x),
                ),
              ),
              Positioned(
                left: x - 28, 
                top: 12, 
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0AB00),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: const Color(0xFFF0AB00).withOpacity(0.5), blurRadius: 10, offset: const Offset(0, 4))
                    ]
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 70, 
                child: Row(
                  children: [
                    _buildNavItem(0, Icons.home_rounded),
                    _buildNavItem(1, Icons.map_rounded),
                    _buildNavItem(2, Icons.person_rounded),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon) {
    final bool isSelected = _currentIndex == index;

    return Expanded(
      child: GestureDetector(
        onTap: () => _onItemTapped(index),
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          height: 70,
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutQuint,
            alignment: isSelected ? const Alignment(0, -0.65) : const Alignment(0, 0.1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutQuint,
              child: Icon(
                icon,
                color: isSelected ? Colors.white : Colors.white54, 
                size: isSelected ? 28 : 24,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHomeTab() {
    if (selectedZoneId == null) {
      // --- THE FIX: Wrapped with RefreshIndicator & AlwaysScrollableScrollPhysics ---
      return RefreshIndicator(
        onRefresh: _handleRefresh,
        color: const Color(0xFF262562),
        backgroundColor: Colors.white,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _getTimeBasedGreeting(),
                style: TextStyle(fontSize: 16, color: Colors.grey.shade600, fontWeight: FontWeight.w600),
              ),
              Text(
                displayName, 
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Color(0xFF262562), letterSpacing: -0.5),
              ),
              const SizedBox(height: 30),
              ZonePicker(onZoneSelected: _handleZoneSelection),
            ],
          ),
        ),
      );
    }
    
    // --- THE FIX: Wrapped Dashboard with RefreshIndicator ---
    return RefreshIndicator(
      onRefresh: _handleRefresh,
      color: const Color(0xFF262562),
      backgroundColor: Colors.white,
      child: _buildDashboard()
    );
  }

  Widget _buildDashboard() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(), // --- THE FIX: Required for pull-to-refresh to always work ---
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildLiveStatusHeader(),
          
          const SizedBox(height: 24),
          
          Text(_getTimeBasedGreeting(), style: TextStyle(fontSize: 16, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
          Row(
            children: [
              Expanded(child: Text(displayName, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.black, letterSpacing: -0.5))),
              GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TopUpPage())),
                child: StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance.collection('Students').doc(user?.uid).snapshots(),
                  builder: (context, snap) {
                    final balance = (snap.data?.data() as Map<String, dynamic>?)?['balance']?.toDouble() ?? 0.0;
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0AB00).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFF0AB00).withOpacity(0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.account_balance_wallet, color: Color(0xFFF0AB00), size: 18),
                          const SizedBox(width: 6),
                          Text("RM ${balance.toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Color(0xFFB8860B))),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 20),

          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('Bookings')
                .where('user_id', isEqualTo: user?.uid)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
                
                var activeDocs = snapshot.data!.docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final status = data['status'] ?? '';
                  return ['confirmed', 'pending', 'arriving'].contains(status);
                }).toList();

                if (activeDocs.isNotEmpty) {
                  activeDocs.sort((a, b) {
                    final tA = ((a.data() as Map)['booking_time'] as Timestamp?)?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0);
                    final tB = ((b.data() as Map)['booking_time'] as Timestamp?)?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0);
                    return tB.compareTo(tA); 
                  });
                  
                  final booking = activeDocs.first;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: _buildLiveActivityPill(booking),
                  );
                }
              }
              return const SizedBox.shrink(); 
            },
          ),

          _buildFeatureStack(),

          const SizedBox(height: 36),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text("Announcements", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
              GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationPage(initialTab: 1))),
                child: const Row(
                  children: [
                    Text("View All", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    Icon(Icons.chevron_right, size: 18),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildServiceUpdatesCarousel(),
          
          const SizedBox(height:80), 
        ],
      ),
    );
  }

  Widget _buildLiveStatusHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))
            ]
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.location_on, size: 16, color: Color(0xFF262562)),
              const SizedBox(width: 8),
              Text(
                selectedZoneName ?? "Select a Zone",
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF262562)),
              ),
            ],
          ),
        ),
        GestureDetector(
          onTap: _resetZone,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))],
            ),
            child: const Icon(Icons.swap_horiz, size: 20, color: Color(0xFF262562)),
          ),
        ),
      ],
    );
  }

  Widget _buildLiveActivityPill(DocumentSnapshot bookingDoc) {
    final data = bookingDoc.data() as Map<String, dynamic>;
    final status = data['status'] ?? 'Unknown';
    final type = data['type'] ?? 'unknown';

    String timeDisplay = data['departure_time'] ?? '';
    DateTime? bookingDate;
    
    if (data['date'] != null) {
      try {
        bookingDate = DateTime.parse(data['date']);
      } catch (_) {}
    }
    
    if (bookingDate == null && data['booking_time'] != null) {
      bookingDate = (data['booking_time'] as Timestamp).toDate();
      if (timeDisplay.isEmpty) {
        timeDisplay = DateFormat('hh:mm a').format(bookingDate);
      }
    }

    String dateContext = "Today";
    if (bookingDate != null) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final bDate = DateTime(bookingDate.year, bookingDate.month, bookingDate.day);
      final diff = bDate.difference(today).inDays;
      
      if (diff == 0) dateContext = "Today";
      else if (diff == 1) dateContext = "Tomorrow";
      else dateContext = DateFormat('dd MMM').format(bookingDate);
    }

    String title = type == 'scheduled' ? "Peak Hour Shuttle" : "On-Demand Ride";
    String locationDisplay = data['pickup_stop_name'] ?? 'Pickup';
    
    if (type == 'scheduled' && data['route_name'] != null) {
      locationDisplay = data['route_name'];
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF262562),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(color: const Color(0xFF262562).withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 8))
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
            child: Icon(type == 'scheduled' ? Icons.directions_bus_rounded : Icons.flash_on_rounded, color: Colors.white),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(title, style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 11, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(color: Colors.green.shade400, borderRadius: BorderRadius.circular(6)),
                      child: Text(status.toUpperCase(), style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.5)),
                    )
                  ],
                ),
                const SizedBox(height: 6),
                Text(locationDisplay, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900), overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text(
                  type == 'scheduled' ? "Departs: $dateContext, $timeDisplay" : "Request Time: $timeDisplay", 
                  style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 12, fontWeight: FontWeight.w600)
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.map, color: Colors.white),
            onPressed: () => setState(() => _currentIndex = 1), 
            style: IconButton.styleFrom(backgroundColor: Colors.white.withOpacity(0.2)),
          )
        ],
      ),
    );
  }

  Widget _buildFeatureStack() {
    return Column(
      children: [
        _buildPredictiveSmartPlannerCard(),
        const SizedBox(height: 16),
        _buildPremiumCard(
          title: "Peak Hour Shuttle",
          subtitle: "Book your fixed-schedule rides",
          icon: Icons.calendar_month,
          gradientColors: [const Color(0xFF0066CC), const Color(0xFF262562)],
          shadowColor: const Color(0xFF262562),
          onTap: () async {
            final result = await Navigator.push(context, MaterialPageRoute(builder: (context) => BookingPage(zoneId: selectedZoneId!, zoneName: selectedZoneName!, initialIndex: 0)));
            if (result == 'goToTracking') {
              setState(() => _currentIndex = 1);
            }
          },
        ),
        const SizedBox(height: 16),
        _buildPremiumCard(
          title: "On-Demand Ride",
          subtitle: "Request an immediate shuttle",
          icon: Icons.flash_on,
          gradientColors: [const Color(0xFFF59E0B), const Color(0xFFEA580C)], 
          shadowColor: const Color(0xFFEA580C),
          onTap: () async {
            final result = await Navigator.push(context, MaterialPageRoute(builder: (context) => BookingPage(zoneId: selectedZoneId!, zoneName: selectedZoneName!, initialIndex: 1)));
            if (result == 'goToTracking') {
              setState(() => _currentIndex = 1);
            }
          },
        ),
      ],
    );
  }

  Widget _buildPredictiveSmartPlannerCard() {
    String currentDay = DateFormat('EEEE').format(DateTime.now());

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('Timetable') 
          .where('user_id', isEqualTo: user?.uid)
          .where('day', isEqualTo: currentDay)
          .snapshots(),
      builder: (context, snapshot) {
        
        String predictiveText = "Optimize your week. See recommended rides.";
        bool isThinking = snapshot.connectionState == ConnectionState.waiting;
        
        if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
          final now = TimeOfDay.now();
          final currentMinutes = now.hour * 60 + now.minute;

          int closestMinutes = 24 * 60; 
          String upcomingTimeDisplay = "";
          bool foundUpcomingClass = false;

          for (var doc in snapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            final startTimeStr = data['start_time'] ?? '';
            final parsedMinutes = _timeToMinutes(startTimeStr);
            
            if (parsedMinutes > currentMinutes && parsedMinutes < closestMinutes) {
              closestMinutes = parsedMinutes;
              upcomingTimeDisplay = startTimeStr;
              foundUpcomingClass = true;
            }
          }

          if (foundUpcomingClass) {
            predictiveText = "Class at $upcomingTimeDisplay? We found a shuttle for you.";
          }
        }

        return _buildPremiumCard(
          title: "Smart Trip Planner",
          subtitle: predictiveText,
          icon: Icons.auto_awesome_motion,
          gradientColors: [const Color(0xFF262562), const Color(0xFF6366F1)], 
          shadowColor: const Color(0xFF6366F1),
          badge: _buildGlassBadge("SMART SYNC"),
          isThinking: isThinking,
          onTap: () async {
            final result = await Navigator.push(context, MaterialPageRoute(builder: (context) => RecommendationPage(zoneId: selectedZoneId!, zoneName: selectedZoneName!)));
            if (result == 'goToTracking') {
              setState(() => _currentIndex = 1); 
            }
          },
        );
      }
    );
  }

  Widget _buildPremiumCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Color> gradientColors,
    required Color shadowColor,
    required VoidCallback onTap,
    Widget? badge,
    bool isThinking = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 140, 
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: LinearGradient(
            colors: gradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: shadowColor.withOpacity(0.3),
              blurRadius: 25,
              offset: const Offset(0, 10),
            )
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              right: -20,
              bottom: -20,
              child: Transform.rotate(
                angle: -0.2,
                child: Icon(icon, size: 140, color: Colors.white.withOpacity(0.15)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (badge != null) badge else const SizedBox(),
                      if (isThinking) const Icon(Icons.blur_on, color: Colors.white70, size: 24),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    title, 
                    style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.5)
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 13, fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGlassBadge(String text) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.3), width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.bolt, color: Colors.white, size: 14),
              const SizedBox(width: 6),
              Text(text, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildServiceUpdatesCarousel() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('Announcements')
          .orderBy('created_at', descending: true)
          .limit(10)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        
        final docs = snapshot.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          if (data['status'] != 'active') return false; 
          final audience = (data['target_audience'] ?? 'all').toString().toLowerCase();
          return audience == 'all' || audience.contains('student');
        }).toList();

        if (docs.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Text("No new announcements.", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w500)),
          );
        }

        final int displayCount = docs.length > 5 ? 5 : docs.length;

        return SizedBox(
          height: 140, 
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: displayCount, 
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              return GestureDetector(
                onTap: () => _showAnnouncementDetails(data['title'] ?? 'Notice', data['message'] ?? '', data['created_at']),
                child: Container(
                  width: 260,
                  margin: const EdgeInsets.only(right: 16),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 15, offset: const Offset(0, 8))
                    ]
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(color: Colors.blue.shade50, shape: BoxShape.circle),
                            child: const Icon(Icons.campaign, color: Colors.blue, size: 16),
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text(data['title'] ?? 'Notice', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14), overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: Text(
                          data['message'] ?? '', 
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 12, height: 1.5), 
                          maxLines: 2, 
                          overflow: TextOverflow.ellipsis
                        )
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class NavBarPainter extends CustomPainter {
  final double x;
  NavBarPainter(this.x);

  @override
  void paint(Canvas canvas, Size size) {
    Paint paint = Paint()
      ..color = const Color(0xFF262562)
      ..style = PaintingStyle.fill;

    Path path = Path();
    double barTop = 20.0;
    double notchRadius = 45.0; 
    double notchDepth = 56.0;  
    
    path.moveTo(0, barTop);
    path.lineTo(x - notchRadius - 15, barTop);
    
    path.cubicTo(
      x - notchRadius, barTop, 
      x - notchRadius + 10, barTop + notchDepth, 
      x, barTop + notchDepth
    );
    
    path.cubicTo(
      x + notchRadius - 10, barTop + notchDepth, 
      x + notchRadius, barTop, 
      x + notchRadius + 15, barTop
    );
    
    path.lineTo(size.width, barTop);
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();

    canvas.drawShadow(path, Colors.black.withOpacity(0.2), 15, false);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant NavBarPainter oldDelegate) {
    return oldDelegate.x != x;
  }
}