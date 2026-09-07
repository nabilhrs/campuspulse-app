import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class NotificationPage extends StatefulWidget {
  final int initialTab; 
  const NotificationPage({super.key, this.initialTab = 0}); 

  @override
  State<NotificationPage> createState() => _NotificationPageState();
}

class _NotificationPageState extends State<NotificationPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final User? user = FirebaseAuth.instance.currentUser;
  
  String _selectedFilter = 'all'; 

  @override
  void initState() {
    super.initState();
    // Sets the tab based on where the user navigated from
    _tabController = TabController(length: 2, vsync: this, initialIndex: widget.initialTab);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _formatDate(dynamic timestampData) {
    if (timestampData == null) return "Just now";
    
    DateTime date;
    if (timestampData is Timestamp) {
      date = timestampData.toDate();
    } else if (timestampData is String) {
      try {
        date = DateTime.parse(timestampData);
      } catch (e) {
        return timestampData; 
      }
    } else {
      return "Just now";
    }

    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0 && now.day == date.day) {
      return "Today, ${DateFormat('hh:mm a').format(date)}";
    } else if (diff.inDays == 1 || (diff.inDays == 0 && now.day != date.day)) {
      return "Yesterday, ${DateFormat('hh:mm a').format(date)}";
    } else if (diff.inDays < 7) {
      return DateFormat('EEEE, hh:mm a').format(date);
    } else {
      return DateFormat('dd MMM yyyy').format(date);
    }
  }

  Future<void> _markAsRead(DocumentReference docRef, bool currentStatus) async {
    if (!currentStatus) {
      await docRef.update({'is_read': true});
    }
  }

  Future<void> _markAllAsRead(List<QueryDocumentSnapshot> docs) async {
    final batch = FirebaseFirestore.instance.batch();
    int count = 0;
    
    for (var doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      if (data['is_read'] != true) {
        batch.update(doc.reference, {'is_read': true});
        count++;
      }
    }
    
    if (count > 0) {
      await batch.commit();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("$count alerts marked as read"), backgroundColor: Colors.green, behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  void _showNotificationDetails(Map<String, dynamic> data, {IconData? customIcon, Color? customColor, bool isAnnouncement = false}) {
    String dateStr = data['timestamp'] != null ? _formatDate(data['timestamp']) : (data['created_at'] != null ? _formatDate(data['created_at']) : '');
    
    final displayIcon = customIcon ?? Icons.notifications_active_rounded;
    final displayColor = customColor ?? const Color(0xFF104C97);
    
    final title = data['title'] ?? (isAnnouncement ? 'Notice' : 'Notification');
    final message = data['message'] ?? data['body'] ?? '';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: displayColor.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(displayIcon, color: displayColor),
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
              
              if (isAnnouncement) ...[
                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 12),
                
                if (data['schedule_id'] != null && data['schedule_id'].toString().isNotEmpty)
                  _buildDetailRow(Icons.calendar_month_rounded, "Schedule", data['schedule_id']),

                if (data['location_name'] != null && data['location_name'].toString().isNotEmpty)
                  _buildDetailRow(Icons.location_on_rounded, "Location", data['location_name']),
                  
                if (data['shuttle_id'] != null && data['shuttle_id'].toString().isNotEmpty)
                  _buildDetailRow(Icons.directions_bus_rounded, "Shuttle", data['shuttle_id']),
                  
                if (data['additional_message'] != null && data['additional_message'].toString().isNotEmpty)
                  _buildDetailRow(Icons.chat_bubble_outline_rounded, "Details", data['additional_message']),
                  
                if (data['status'] == 'resolved' && data['resolution_notes'] != null)
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.shade200)
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.check_circle_rounded, color: Colors.green, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("Resolved", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12)),
                              const SizedBox(height: 2),
                              Text(data['resolution_notes'], style: TextStyle(color: Colors.green.shade800, fontSize: 13, fontWeight: FontWeight.w500)),
                              if (data['resolved_at'] != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4.0),
                                  child: Text(_formatDate(data['resolved_at']), style: TextStyle(color: Colors.green.shade600, fontSize: 10, fontWeight: FontWeight.w600)),
                                )
                            ],
                          )
                        )
                      ]
                    )
                  )
              ]
            ],
          ),
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF104C97),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
              ),
              child: const Text("Done", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          SizedBox(width: 70, child: Text("$label:", style: const TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w600))),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87))),
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
        title: const Text(
          "Notification Center", 
          style: TextStyle(color: Color(0xFF104C97), fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.5)
        ),
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
              tabs: const [Tab(text: "My Alerts"), Tab(text: "Campus News")],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        physics: const BouncingScrollPhysics(),
        children: [
          _buildPersonalAlertsTab(),
          _buildCampusNewsTab(),
        ],
      ),
    );
  }

  Widget _buildPersonalAlertsTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('Notifications')
          .where('user_id', isEqualTo: user?.uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text("Error: ${snapshot.error}", style: const TextStyle(color: Colors.red)));
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Color(0xFF104C97)));

        var allDocs = snapshot.data!.docs.toList();
        allDocs.sort((a, b) {
          final dataA = a.data() as Map<String, dynamic>;
          final dataB = b.data() as Map<String, dynamic>;
          DateTime timeA = DateTime.fromMillisecondsSinceEpoch(0);
          DateTime timeB = DateTime.fromMillisecondsSinceEpoch(0);
          if (dataA['timestamp'] is Timestamp) timeA = (dataA['timestamp'] as Timestamp).toDate();
          if (dataB['timestamp'] is Timestamp) timeB = (dataB['timestamp'] as Timestamp).toDate();
          return timeB.compareTo(timeA); 
        });

        List<QueryDocumentSnapshot> filteredDocs = allDocs;
        if (_selectedFilter == 'unread') {
          filteredDocs = allDocs.where((doc) => (doc.data() as Map<String, dynamic>)['is_read'] != true).toList();
        } else if (_selectedFilter == 'rides') {
          // --- THE FIX: Make sure the new notification types are caught by the 'Rides' filter
          filteredDocs = allDocs.where((doc) {
            final type = (doc.data() as Map<String, dynamic>)['type'] ?? '';
            return ['booking_confirmed', 'driver_arriving', 'arrived', 'trip_started', 'trip_completed', 'reminder', 'shuttle_full', 'timeout', 'system_alert'].contains(type);
          }).toList();
        }

        return Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        children: [
                          _buildFilterChip("All", 'all'),
                          _buildFilterChip("Unread", 'unread'),
                          _buildFilterChip("Ride Updates", 'rides'),
                        ],
                      ),
                    ),
                  ),
                  if (allDocs.any((doc) => (doc.data() as Map<String, dynamic>)['is_read'] != true))
                    IconButton(
                      icon: const Icon(Icons.checklist_rounded, color: Color(0xFF104C97)),
                      tooltip: "Mark all as read",
                      onPressed: () => _markAllAsRead(allDocs),
                    )
                ],
              ),
            ),
            
            Expanded(
              child: filteredDocs.isEmpty
                ? _buildEmptyState(
                    _selectedFilter == 'unread' ? Icons.mark_email_read_rounded : Icons.notifications_off_rounded, 
                    _selectedFilter == 'unread' ? "No Unread Alerts" : "No Alerts Yet", 
                    "You're all caught up! Your personal ride alerts and reminders will appear here."
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    physics: const BouncingScrollPhysics(),
                    itemCount: filteredDocs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final doc = filteredDocs[index];
                      final data = doc.data() as Map<String, dynamic>;
                      final bool isRead = data['is_read'] ?? false;

                      return GestureDetector(
                        onTap: () {
                          _markAsRead(doc.reference, isRead);
                          _showNotificationDetails(
                            data,
                            customIcon: _getAlertIcon(data['type']),
                            customColor: _getAlertColor(data['type']),
                            isAnnouncement: false,
                          );
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: isRead ? Colors.white : Colors.blue.shade50.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: isRead ? Colors.grey.shade100 : Colors.blue.shade200),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: _getAlertColor(data['type']).withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(_getAlertIcon(data['type']), color: _getAlertColor(data['type']), size: 24),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            data['title'] ?? 'Notification',
                                            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: isRead ? Colors.black87 : const Color(0xFF104C97)),
                                          ),
                                        ),
                                        if (!isRead)
                                          Container(
                                            margin: const EdgeInsets.only(left: 8, top: 4),
                                            width: 8, height: 8,
                                            decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                                          )
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      data['body'] ?? data['message'] ?? '',
                                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13, height: 1.4, fontWeight: isRead ? FontWeight.normal : FontWeight.w600),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      data['timestamp'] != null ? _formatDate(data['timestamp']) : (data['created_at'] != null ? _formatDate(data['created_at']) : 'Just now'),
                                      style: TextStyle(color: Colors.grey.shade400, fontSize: 11, fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFilterChip(String label, String value) {
    bool isSelected = _selectedFilter == value;
    return GestureDetector(
      onTap: () => setState(() => _selectedFilter = value),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF104C97) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? const Color(0xFF104C97) : Colors.grey.shade300),
        ),
        child: Text(
          label, 
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey.shade600, 
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            fontSize: 13
          )
        ),
      ),
    );
  }

  Widget _buildCampusNewsTab() {
    if (user == null) return const Center(child: CircularProgressIndicator());

    // 1. Fetch user's active bookings FIRST to determine which specific schedule IDs they care about
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('Bookings')
          .where('user_id', isEqualTo: user!.uid)
          .where('status', whereIn: ['pending', 'confirmed', 'arriving', 'on_board', 'onboard'])
          .snapshots(),
      builder: (context, bookingSnapshot) {
        if (bookingSnapshot.hasError) return const Center(child: Text("Error loading bookings"));
        
        List<String> activeScheduleIds = [];
        List<String> activeShuttleIds = [];

        if (bookingSnapshot.hasData) {
          for (var doc in bookingSnapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            if (data['schedule_id'] != null && data['schedule_id'].toString().isNotEmpty) {
              activeScheduleIds.add(data['schedule_id']);
            }
            if (data['shuttle_id'] != null && data['shuttle_id'].toString().isNotEmpty) {
              activeShuttleIds.add(data['shuttle_id']);
            }
          }
        }

        // 2. Fetch the announcements
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('Announcements')
              .orderBy('created_at', descending: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) return Center(child: Text("Error: ${snapshot.error}", style: const TextStyle(color: Colors.red)));
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Color(0xFF104C97)));

            final docs = snapshot.data!.docs.where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              
              if (!['active', 'resolved'].contains(data['status'])) return false; 
              
              final audience = (data['target_audience'] ?? 'all').toString().toLowerCase();
              if (audience != 'all' && !audience.contains('student')) return false;

              // --- SMART TARGETING LOGIC ---
              final scheduleId = data['schedule_id']?.toString() ?? '';
              final shuttleId = data['shuttle_id']?.toString() ?? '';

              // If it's a specific alert tied to a schedule/shuttle, ONLY show it if the user is booked on it
              if (scheduleId.isNotEmpty || shuttleId.isNotEmpty) {
                bool isUserAffected = false;
                if (scheduleId.isNotEmpty && activeScheduleIds.contains(scheduleId)) isUserAffected = true;
                if (shuttleId.isNotEmpty && activeShuttleIds.contains(shuttleId)) isUserAffected = true;
                
                if (!isUserAffected) return false; 
              }

              return true; // General broadcasts (no specific IDs) pass through
            }).toList();

            if (docs.isEmpty) {
              return _buildEmptyState(Icons.campaign_outlined, "No Campus News", "There are no active announcements at the moment.");
            }

            return ListView.separated(
              padding: const EdgeInsets.all(24),
              physics: const BouncingScrollPhysics(),
              itemCount: docs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 16),
              itemBuilder: (context, index) {
                final data = docs[index].data() as Map<String, dynamic>;
                
                final String tag = data['tag'] ?? '#Update';
                final String status = data['status'] ?? 'active';
                
                Color iconColor = Colors.blue.shade700;
                Color bgColor = Colors.blue.shade50;
                IconData iconData = Icons.campaign_rounded;
                
                if (status == 'resolved') {
                   iconColor = Colors.green;
                   bgColor = Colors.green.shade50;
                   iconData = Icons.check_circle_rounded;
                } else if (tag == '#Emergency') {
                   iconColor = Colors.redAccent;
                   bgColor = Colors.red.shade50;
                   iconData = Icons.error_rounded;
                } else if (tag == '#Warning') {
                   iconColor = Colors.orange.shade700;
                   bgColor = Colors.orange.shade50;
                   iconData = Icons.warning_rounded;
                }
                
                return GestureDetector(
                  onTap: () => _showNotificationDetails(
                    data,
                    customIcon: iconData,
                    customColor: iconColor,
                    isAnnouncement: true
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: status == 'resolved' ? Colors.green.shade200 : Colors.grey.shade200),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 15, offset: const Offset(0, 5))],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
                              child: Icon(iconData, color: iconColor, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    data['title'] ?? 'Notice',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900, 
                                      fontSize: 16, 
                                      color: status == 'resolved' ? Colors.grey : Colors.black87,
                                      decoration: status == 'resolved' ? TextDecoration.lineThrough : null
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Text(
                                        tag,
                                        style: TextStyle(color: iconColor, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                                      ),
                                      if (status == 'resolved') ...[
                                        const SizedBox(width: 6),
                                        const Text("•", style: TextStyle(color: Colors.grey, fontSize: 10)),
                                        const SizedBox(width: 6),
                                        const Text("RESOLVED", style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                                      ]
                                    ],
                                  )
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          data['message'] ?? '',
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 13, height: 1.5),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        
                        if (data['location_name'] != null && data['location_name'].toString().isNotEmpty)
                           Padding(
                             padding: const EdgeInsets.only(top: 12.0),
                             child: Row(
                               children: [
                                 const Icon(Icons.location_on, size: 14, color: Colors.grey),
                                 const SizedBox(width: 4),
                                 Expanded(child: Text(data['location_name'], style: const TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                               ],
                             ),
                           ),
                           
                        const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1)),
                        
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              data['created_at'] != null ? _formatDate(data['created_at']) : '',
                              style: TextStyle(color: Colors.grey.shade400, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                              child: const Text("Official Update", style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.w800)),
                            )
                          ],
                        )
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      }
    );
  }

  Widget _buildEmptyState(IconData icon, String title, String subtitle) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20)]),
              child: Icon(icon, size: 50, color: Colors.grey.shade300),
            ),
            const SizedBox(height: 24),
            Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
            const SizedBox(height: 8),
            Text(subtitle, style: TextStyle(color: Colors.grey.shade500, fontSize: 14, height: 1.4), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  // --- THE FIX: Themed colors for the newly added alert types ---
  Color _getAlertColor(String? type) {
    switch (type) {
      case 'booking_confirmed': return Colors.green;
      case 'driver_arriving': return Colors.blue;
      case 'arrived': return Colors.teal; 
      case 'trip_started': return const Color(0xFF262562); 
      case 'trip_completed': return Colors.green.shade700; 
      case 'reminder': return const Color(0xFFF0AB00); 
      case 'shuttle_full': return Colors.orange;
      case 'timeout': return Colors.redAccent;
      case 'system_alert': return Colors.red;
      case 'dispatch_alert': return Colors.purple;
      default: return const Color(0xFF104C97);
    }
  }

  // --- THE FIX: Specific Icons for the newly added alert types ---
  IconData _getAlertIcon(String? type) {
    switch (type) {
      case 'booking_confirmed': return Icons.check_circle_rounded;
      case 'driver_arriving': return Icons.directions_bus_rounded;
      case 'arrived': return Icons.location_on_rounded; 
      case 'trip_started': return Icons.rocket_launch_rounded; 
      case 'trip_completed': return Icons.flag_rounded; 
      case 'reminder': return Icons.alarm_rounded; 
      case 'shuttle_full': return Icons.groups_rounded;
      case 'timeout': return Icons.timer_off_rounded;
      case 'system_alert': return Icons.warning_rounded;
      case 'dispatch_alert': return Icons.campaign_rounded;
      default: return Icons.notifications_rounded;
    }
  }
}