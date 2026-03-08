import 'package:flutter/material.dart';
import 'package:campuspulse/modules/booking/schedule_booking.dart';
import 'package:campuspulse/modules/booking/ondemand_booking.dart';

class BookingPage extends StatefulWidget {
  final String zoneId;
  final String zoneName;
  final int initialIndex; // 1. Added this parameter

  const BookingPage({
    super.key, 
    required this.zoneId, 
    required this.zoneName,
    this.initialIndex = 0, // Default to 0 (Scheduled)
  });

  @override
  State<BookingPage> createState() => _BookingPageState();
}

class _BookingPageState extends State<BookingPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    // 2. Initialize the controller with the passed index
    _tabController = TabController(
      length: 2, 
      vsync: this, 
      initialIndex: widget.initialIndex
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Booking: ${widget.zoneName}"),
        backgroundColor: const Color(0xFF104C97),
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFF0AB00),
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(icon: Icon(Icons.calendar_month), text: "Scheduled"),
            Tab(icon: Icon(Icons.directions_car), text: "On-Demand"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          ScheduleBooking(zoneId: widget.zoneId),
          OnDemandBooking(zoneId: widget.zoneId),
        ],
      ),
    );
  }
}