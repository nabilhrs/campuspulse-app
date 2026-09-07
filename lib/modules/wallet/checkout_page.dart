import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:campuspulse/modules/wallet/topup_page.dart';
import 'package:campuspulse/modules/home/policies_page.dart';

class CheckoutPage extends StatefulWidget {
  final String tripType; 
  final String zoneId;
  final String zoneName;
  final String pickupStopId;
  final String pickupStopName;

  final DocumentSnapshot? scheduleDoc;
  final String? routeId;
  final String? routeName;
  final String? pickupTime;
  final String? date;
  final String? displayDate;
  final String? shuttleId;
  final String? driverId;
  final String? driverName;

  final String? dropoffStopId;
  final String? dropoffStopName;
  
  final double? pickupLat;
  final double? pickupLng;

  const CheckoutPage({
    super.key,
    required this.tripType,
    required this.zoneId,
    required this.zoneName,
    required this.pickupStopId,
    required this.pickupStopName,
    this.scheduleDoc,
    this.routeId,
    this.routeName,
    this.pickupTime,
    this.date,
    this.displayDate,
    this.shuttleId,
    this.driverId,
    this.driverName,
    this.dropoffStopId,
    this.dropoffStopName,
    this.pickupLat,
    this.pickupLng,
  });

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  final User? user = FirebaseAuth.instance.currentUser;
  bool _isProcessing = false;
  static const double _baseFare = 2.0;
  static const double _serviceFee = 0.0;
  double get _totalFare => _baseFare + _serviceFee;

  late TapGestureRecognizer _policyRecognizer;

  @override
  void initState() {
    super.initState();
    _policyRecognizer = TapGestureRecognizer()
      ..onTap = () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const PoliciesPage()));
      };
  }

  @override
  void dispose() {
    _policyRecognizer.dispose();
    super.dispose();
  }

  void _showFloatingSnackBar(String message, {Color color = Colors.red}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.only(bottom: 15, left: 20, right: 20),
        elevation: 8,
      ),
    );
  }

  Future<void> _confirmAndPay() async {
    if (user == null) return;
    setState(() => _isProcessing = true);

    try {
      final studentRef = FirebaseFirestore.instance.collection('Students').doc(user!.uid);

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final studentSnap = await transaction.get(studentRef);
        if (!studentSnap.exists) throw Exception("Student record not found.");
        final currentBalance = (studentSnap.data()?['balance'] ?? 0.0).toDouble();

        if (currentBalance < _totalFare) throw Exception("Insufficient balance");

        if (widget.tripType == 'scheduled' && widget.scheduleDoc != null) {
          final freshSchedule = await transaction.get(widget.scheduleDoc!.reference);
          final freshData = freshSchedule.data() as Map<String, dynamic>;
          final int freshBooked = freshData['booked_count'] ?? 0;
          if (freshBooked >= (freshData['capacity'] ?? 13)) throw Exception("Seats no longer available");

          transaction.update(widget.scheduleDoc!.reference, {'booked_count': freshBooked + 1});
        }

        transaction.update(studentRef, {'balance': currentBalance - _totalFare});

        final bookingRef = FirebaseFirestore.instance.collection('Bookings').doc();
        final Map<String, dynamic> bookingData = {
          'user_id': user!.uid,
          'zone_id': widget.zoneId,
          'zone_name': widget.zoneName,
          'pickup_stop_id': widget.pickupStopId,
          'pickup_stop_name': widget.pickupStopName,
          'booking_time': FieldValue.serverTimestamp(),
          'fare': _totalFare,
        };

        if (widget.tripType == 'scheduled') {
          bookingData.addAll({
            'type': 'scheduled',
            'status': 'confirmed',
            'schedule_id': widget.scheduleDoc?.id,
            'route_id': widget.routeId,
            'route_name': widget.routeName,
            'departure_time': widget.pickupTime,
            'date': widget.date,
            'shuttle_id': widget.shuttleId,
            'driver_id': widget.driverId,
            'driver_name': widget.driverName,
            // --- THE FIX: Explicitly save the Dropoff Stop for scheduled trips ---
            'dropoff_stop_id': widget.dropoffStopId,
            'dropoff_stop_name': widget.dropoffStopName,
          });
        } else {
          bookingData.addAll({
            'type': 'ondemand',
            'status': 'searching',
            'candidate_driver_id': widget.driverId,
            'pickup_lat': widget.pickupLat,
            'pickup_lng': widget.pickupLng,
            'rejected_by': [],
            'dropoff_stop_id': widget.dropoffStopId,
            'dropoff_stop_name': widget.dropoffStopName,
            'request_time': FieldValue.serverTimestamp(),
          });
        }

        transaction.set(bookingRef, bookingData);

        final txnRef = FirebaseFirestore.instance.collection('Transactions').doc();
        final description = widget.tripType == 'scheduled'
            ? 'Scheduled: ${widget.routeName ?? "Fixed Route"}'
            : 'On-Demand: ${widget.pickupStopName} → ${widget.dropoffStopName ?? "Dest"}';

        transaction.set(txnRef, {
          'user_id': user!.uid,
          'type': 'debit',
          'amount': _totalFare,
          'description': description,
          'reference_id': bookingRef.id, 
          'timestamp': FieldValue.serverTimestamp(),
        });
      });

      if (!mounted) return;
      setState(() => _isProcessing = false);
      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 20),
              Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.green.shade50, shape: BoxShape.circle), child: const Icon(Icons.check_circle, color: Colors.green, size: 60)),
              const SizedBox(height: 20),
              Text(widget.tripType == 'scheduled' ? "Booking Confirmed!" : "Request Sent!", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900), textAlign: TextAlign.center),
              const SizedBox(height: 10),
              Text(
                widget.tripType == 'scheduled'
                    ? "Your seat has been reserved and RM ${_totalFare.toStringAsFixed(2)} has been deducted."
                    : "Pinging nearby drivers. RM ${_totalFare.toStringAsFixed(2)} has been deducted.",
                style: const TextStyle(color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context); 
                    Navigator.pop(context, 'goToTracking'); 
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF104C97), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  child: const Text("Track Ride", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      final msg = e.toString();
      if (msg.contains("Insufficient balance")) {
        _showFloatingSnackBar("Insufficient Campus Credits! Please top up first.");
      } else if (msg.contains("Seats no longer available")) {
        _showFloatingSnackBar("This shuttle is now full. Please try another schedule.");
      } else {
        _showFloatingSnackBar("Payment failed: $msg");
      }
      
      if (mounted) setState(() => _isProcessing = false);
    } 
  }

  Widget _buildLoadingOverlay() {
    return Positioned.fill(
      child: TweenAnimationBuilder(
        tween: Tween<double>(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 250),
        builder: (context, value, child) {
          return Opacity(
            opacity: value,
            child: child,
          );
        },
        child: AbsorbPointer(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            child: Container(
              color: Colors.black.withOpacity(0.3),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 36),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, 10))
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 50,
                        height: 50,
                        child: CircularProgressIndicator(color: Color(0xFF104C97), strokeWidth: 4),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        "Processing Payment", 
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF104C97), letterSpacing: -0.5)
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Please do not close the app", 
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 13, fontWeight: FontWeight.w500)
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value, {Color? iconColor}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: (iconColor ?? Colors.grey).withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, size: 16, color: iconColor ?? const Color(0xFF104C97))),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600)), const SizedBox(height: 2), Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87))])),
      ],
    );
  }

  Widget _buildPriceRow(String label, String value, {bool isBold = false, bool isLight = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: isBold ? 16 : 14, fontWeight: isBold ? FontWeight.w900 : FontWeight.w600, color: isLight ? Colors.grey : Colors.black87)),
        Text(value, style: TextStyle(fontSize: isBold ? 20 : 14, fontWeight: isBold ? FontWeight.w900 : FontWeight.w600, color: isBold ? const Color(0xFF104C97) : (isLight ? Colors.grey : Colors.black87))),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isScheduled = widget.tripType == 'scheduled';

    return Stack(
      children: [
        Scaffold(
          backgroundColor: const Color(0xFFF8F9FA),
          appBar: AppBar(
            backgroundColor: const Color(0xFFF8F9FA),
            elevation: 0,
            scrolledUnderElevation: 0,
            iconTheme: const IconThemeData(color: Color(0xFF104C97)),
            centerTitle: true,
            title: const Text("Booking Summary", style: TextStyle(color: Color(0xFF104C97), fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 15, offset: const Offset(0, 5))],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(color: isScheduled ? const Color(0xFF104C97).withOpacity(0.1) : const Color(0xFFEA580C).withOpacity(0.1), shape: BoxShape.circle),
                            child: Icon(isScheduled ? Icons.calendar_month_rounded : Icons.flash_on_rounded, color: isScheduled ? const Color(0xFF104C97) : const Color(0xFFEA580C), size: 22),
                          ),
                          const SizedBox(width: 12),
                          Text(isScheduled ? "Peak Hour Shuttle" : "On-Demand Ride", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.3)),
                        ],
                      ),
                      const SizedBox(height: 24),

                      if (isScheduled) ...[
                        _buildInfoRow(Icons.route, "Route", widget.routeName ?? "N/A"),
                        const SizedBox(height: 16),
                        // --- THE FIX: Standardized Pickup/Dropoff UI for Scheduled Trips ---
                        _buildInfoRow(Icons.circle, "Pickup", widget.pickupStopName, iconColor: Colors.green),
                        const SizedBox(height: 16),
                        _buildInfoRow(Icons.square, "Dropoff", widget.dropoffStopName ?? "N/A", iconColor: Colors.redAccent),
                        const SizedBox(height: 16),
                        _buildInfoRow(Icons.access_time, "Pickup Time", widget.pickupTime ?? "N/A"),
                        const SizedBox(height: 16),
                        _buildInfoRow(Icons.calendar_today, "Date", widget.displayDate ?? widget.date ?? "N/A"),
                      ] else ...[
                        _buildInfoRow(Icons.circle, "Pickup", widget.pickupStopName, iconColor: Colors.green),
                        const SizedBox(height: 16),
                        _buildInfoRow(Icons.square, "Dropoff", widget.dropoffStopName ?? "N/A", iconColor: Colors.redAccent),
                      ],

                      const SizedBox(height: 16),
                      _buildInfoRow(Icons.map, "Zone", widget.zoneName),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 15, offset: const Offset(0, 5))]),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Payment", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.3)),
                      const SizedBox(height: 20),
                      _buildPriceRow("Base Fare", "RM ${_baseFare.toStringAsFixed(2)}"),
                      const SizedBox(height: 12),
                      _buildPriceRow("Service Fee", "RM ${_serviceFee.toStringAsFixed(2)}", isLight: true),
                      const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Divider()),
                      _buildPriceRow("Total", "RM ${_totalFare.toStringAsFixed(2)}", isBold: true),
                      
                      if (isScheduled)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.info_outline, size: 16, color: Colors.grey.shade500),
                              const SizedBox(width: 8),
                              Expanded(child: Text("Cancellation Policy: Cancelling within 15 minutes of scheduled departure incurs a 50% penalty fee (RM 1.00 deduction).", style: TextStyle(color: Colors.grey.shade600, fontSize: 11, fontWeight: FontWeight.w600))),
                            ]
                          )
                        )
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance.collection('Students').doc(user?.uid).snapshots(),
                  builder: (context, snapshot) {
                    final balance = (snapshot.data?.data() as Map<String, dynamic>?)?['balance']?.toDouble() ?? 0.0;
                    final bool canAfford = balance >= _totalFare;

                    return Column(
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: canAfford ? Colors.green.shade50 : Colors.red.shade50,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: canAfford ? Colors.green.shade200 : Colors.red.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.account_balance_wallet, color: canAfford ? Colors.green : Colors.redAccent, size: 24),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text("Your Balance", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey)),
                                    Text("RM ${balance.toStringAsFixed(2)}", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: canAfford ? Colors.green.shade700 : Colors.red.shade700)),
                                  ],
                                ),
                              ),
                              if (canAfford) Icon(Icons.check_circle, color: Colors.green.shade600, size: 28)
                              else Icon(Icons.error, color: Colors.red.shade600, size: 28),
                            ],
                          ),
                        ),

                        if (!canAfford) ...[
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(16)),
                            child: Row(
                              children: [
                                const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 20),
                                const SizedBox(width: 10),
                                const Expanded(child: Text("Insufficient Campus Credits", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 14))),
                                TextButton(
                                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TopUpPage())),
                                  child: const Text("Top Up", style: TextStyle(color: Color(0xFF104C97), fontWeight: FontWeight.w900)),
                                ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 28),

                        SizedBox(
                          width: double.infinity,
                          height: 60,
                          child: ElevatedButton(
                            onPressed: (canAfford && !_isProcessing) ? _confirmAndPay : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: canAfford ? const Color(0xFF104C97) : Colors.grey.shade400,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: Colors.grey.shade300,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              elevation: canAfford ? 8 : 0,
                              shadowColor: const Color(0xFF104C97).withOpacity(0.5),
                            ),
                            child: _isProcessing
                                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(canAfford ? Icons.lock : Icons.lock_outline, size: 20),
                                      const SizedBox(width: 10),
                                      Text(
                                        canAfford ? "Confirm & Pay · RM ${_totalFare.toStringAsFixed(2)}" : "Insufficient Credits",
                                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, letterSpacing: 0.3),
                                      ),
                                    ],
                                  ),
                          ),
                        ),

                        const SizedBox(height: 16),
                        
                        // --- NEW: Contextual Policy Link ---
                        Center(
                          child: RichText(
                            textAlign: TextAlign.center,
                            text: TextSpan(
                              text: "By confirming, you agree to our ",
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 12, fontWeight: FontWeight.w500),
                              children: [
                                TextSpan(
                                  text: "Refund & Cancellation Policy",
                                  style: const TextStyle(color: Color(0xFF104C97), fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
                                  recognizer: _policyRecognizer,
                                ),
                                const TextSpan(text: "."),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 40),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        
        if (_isProcessing) _buildLoadingOverlay(),
      ],
    );
  }
}