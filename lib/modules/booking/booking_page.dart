import 'package:flutter/material.dart';
import 'package:campuspulse/modules/booking/schedule_booking.dart';
import 'package:campuspulse/modules/booking/ondemand_booking.dart';

class BookingPage extends StatefulWidget {
  final String zoneId;
  final String zoneName;
  final int initialIndex; 
  final String? initialPickupStopId;
  final String? initialPickupStopName;
  final String? initialDropoffStopId;
  final String? initialDropoffStopName;

  const BookingPage({
    super.key, 
    required this.zoneId, 
    required this.zoneName,
    this.initialIndex = 0, 
    this.initialPickupStopId,
    this.initialPickupStopName,
    this.initialDropoffStopId,
    this.initialDropoffStopName,
  });

  @override
  State<BookingPage> createState() => _BookingPageState();
}

class _BookingPageState extends State<BookingPage> {
  late PageController _pageController;
  late int _selectedIndex;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  void _onHeaderTapped(int index) {
    if (_selectedIndex == index) return;
    _pageController.animateToPage(
      index, 
      duration: const Duration(milliseconds: 300), 
      curve: Curves.easeOutQuint,
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
        iconTheme: const IconThemeData(color: Color(0xFF262562)),
        centerTitle: true,
        title: Column(
          children: [
            const Text("Booking For", style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600, letterSpacing: 1)),
            Text(
              widget.zoneName, 
              style: const TextStyle(color: Color(0xFF262562), fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.5)
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          _buildModernSegmentedControl(),
          Expanded(
            child: PageView(
              controller: _pageController,
              onPageChanged: _onPageChanged,
              physics: const BouncingScrollPhysics(),
              children: [
                ScheduleBooking(zoneId: widget.zoneId, zoneName: widget.zoneName), 
                OnDemandBooking(
                  zoneId: widget.zoneId, 
                  zoneName: widget.zoneName,
                  initialPickupStopId: widget.initialPickupStopId,
                  initialPickupStopName: widget.initialPickupStopName,
                  initialDropoffStopId: widget.initialDropoffStopId,
                  initialDropoffStopName: widget.initialDropoffStopName,
                ), 
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernSegmentedControl() {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 10, 24, 16),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          _buildSegmentButton(0, "Peak Hour", Icons.calendar_month_rounded),
          _buildSegmentButton(1, "On-Demand", Icons.flash_on_rounded),
        ],
      ),
    );
  }

  Widget _buildSegmentButton(int index, String title, IconData icon) {
    final isSelected = _selectedIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => _onHeaderTapped(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: isSelected ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 4))] : [],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: isSelected ? const Color(0xFF262562) : Colors.grey.shade500),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  fontSize: 13,
                  color: isSelected ? const Color(0xFF262562) : Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}