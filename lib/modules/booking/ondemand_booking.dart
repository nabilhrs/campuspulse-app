import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:campuspulse/modules/wallet/checkout_page.dart';

class OnDemandBooking extends StatefulWidget {
  final String zoneId;
  final String zoneName; 
  final String? initialPickupStopId;
  final String? initialPickupStopName;
  final String? initialDropoffStopId;
  final String? initialDropoffStopName;

  const OnDemandBooking({
    super.key, 
    required this.zoneId, 
    required this.zoneName,
    this.initialPickupStopId,
    this.initialPickupStopName,
    this.initialDropoffStopId,
    this.initialDropoffStopName,
  });

  @override
  State<OnDemandBooking> createState() => _OnDemandBookingState();
}

class _OnDemandBookingState extends State<OnDemandBooking> {
  final User? user = FirebaseAuth.instance.currentUser;
  bool _isLoading = false;
  
  String? _selectedPickupStopId;
  String? _selectedPickupStopName;

  String? _selectedDropoffStopId;
  String? _selectedDropoffStopName;

  late Stream<QuerySnapshot> _stopsStream;
  late Stream<QuerySnapshot> _allBookingsStream;

  @override
  void initState() {
    super.initState();

    _selectedPickupStopId = widget.initialPickupStopId;
    _selectedPickupStopName = widget.initialPickupStopName;
    _selectedDropoffStopId = widget.initialDropoffStopId;
    _selectedDropoffStopName = widget.initialDropoffStopName;

    _stopsStream = FirebaseFirestore.instance.collection('Stops').where('status', isEqualTo: 'active').snapshots();
    
    _allBookingsStream = FirebaseFirestore.instance
        .collection('Bookings')
        .where('user_id', isEqualTo: user?.uid ?? '')
        .snapshots();
  }

  void _showFloatingSnackBar(String message, {Color color = Colors.red}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message, style: const TextStyle(fontWeight: FontWeight.bold)), backgroundColor: color, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), margin: const EdgeInsets.only(bottom: 60, left: 20, right: 20), elevation: 8));
  }

  void _flipLocations() {
    if (_selectedPickupStopId == null && _selectedDropoffStopId == null) return;
    setState(() {
      final tempId = _selectedPickupStopId;
      final tempName = _selectedPickupStopName;
      _selectedPickupStopId = _selectedDropoffStopId;
      _selectedPickupStopName = _selectedDropoffStopName;
      _selectedDropoffStopId = tempId;
      _selectedDropoffStopName = tempName;
    });
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371; 
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLon = (lon2 - lon1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
              math.cos(lat1 * math.pi / 180) * math.cos(lat2 * math.pi / 180) *
              math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c; 
  }

  Future<void> _requestRide() async {
    if (_selectedPickupStopId == null || _selectedDropoffStopId == null) {
      _showFloatingSnackBar("Please select Pickup and Dropoff locations.");
      return;
    }
    if (_selectedPickupStopId == _selectedDropoffStopId) {
      _showFloatingSnackBar("Pickup and Dropoff locations cannot be the same.");
      return;
    }

    setState(() => _isLoading = true);

    double? pLat;
    double? pLng;
    String? candidateDriverId;

    try {
      final stopDoc = await FirebaseFirestore.instance.collection('Stops').doc(_selectedPickupStopId).get();
      if (stopDoc.exists) {
        final data = stopDoc.data()!;
        pLat = (data['lat'] is num) ? (data['lat'] as num).toDouble() : double.tryParse(data['lat'].toString());
        pLng = (data['lng'] is num) ? (data['lng'] as num).toDouble() : double.tryParse(data['lng'].toString());
      }

      if (pLat != null && pLng != null) {
        final shuttlesSnap = await FirebaseFirestore.instance.collection('Shuttles')
            .where('is_online', isEqualTo: true)
            .where('job_status', isEqualTo: 'idle')
            .get();

        double minDistance = double.infinity;
        String? nearestShuttleId;

        for (var doc in shuttlesSnap.docs) {
          final data = doc.data();
          if (data['current_lat'] != null && data['current_lng'] != null) {
            double sLat = (data['current_lat'] is num) ? (data['current_lat'] as num).toDouble() : double.tryParse(data['current_lat'].toString()) ?? 0.0;
            double sLng = (data['current_lng'] is num) ? (data['current_lng'] as num).toDouble() : double.tryParse(data['current_lng'].toString()) ?? 0.0;
            
            double dist = _calculateDistance(pLat, pLng, sLat, sLng);
            if (dist < minDistance) {
              minDistance = dist;
              nearestShuttleId = doc.id;
            }
          }
        }

        if (nearestShuttleId != null) {
          final driverSnap = await FirebaseFirestore.instance.collection('Staffs')
              .where('role', isEqualTo: 'driver')
              .where('assigned_shuttle_id', isEqualTo: nearestShuttleId)
              .limit(1).get();
          if (driverSnap.docs.isNotEmpty) {
            candidateDriverId = driverSnap.docs.first.id;
          }
        }
      }
    } catch (e) {
      debugPrint("Error finding candidate driver: $e");
    } 

    if (!mounted) return;

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CheckoutPage(
          tripType: 'ondemand',
          zoneId: widget.zoneId,
          zoneName: widget.zoneName,
          pickupStopId: _selectedPickupStopId!,
          pickupStopName: _selectedPickupStopName ?? 'Selected Stop',
          dropoffStopId: _selectedDropoffStopId,
          dropoffStopName: _selectedDropoffStopName,
          pickupLat: pLat,
          pickupLng: pLng,
          driverId: candidateDriverId,
        ),
      ),
    );

    if (mounted) setState(() => _isLoading = false);
    if (result == 'goToTracking' && mounted) Navigator.pop(context, 'goToTracking');
  }

  Future<void> _handleTimeoutAndRefund(DocumentSnapshot doc) async {
    if (!mounted) return;
    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final fresh = await tx.get(doc.reference);
        if (fresh['status'] != 'pending' && fresh['status'] != 'searching' && fresh['status'] != 'admin_review') return; 
        
        final studentRef = FirebaseFirestore.instance.collection('Students').doc(user!.uid);
        final studentSnap = await tx.get(studentRef);
        
        final fare = (fresh.data() as Map<String, dynamic>)['fare']?.toDouble() ?? 2.0;
        tx.update(doc.reference, {'status': 'expired'});
        
        if (studentSnap.exists) {
          final balance = (studentSnap.data()?['balance'] ?? 0.0).toDouble();
          tx.update(studentRef, {'balance': balance + fare});
        }
        
        final txnRef = FirebaseFirestore.instance.collection('Transactions').doc();
        tx.set(txnRef, {
          'user_id': user!.uid,
          'type': 'credit',
          'amount': fare,
          'description': 'Refund: Request Timeout',
          'reference_id': doc.id,
          'timestamp': FieldValue.serverTimestamp(),
        });
      });
    } catch (e) {
      debugPrint("Timeout refund error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: _allBookingsStream, 
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Color(0xFF262562)));

        bool hasActiveOnDemand = false;
        DocumentSnapshot? activeDoc;
        
        Map<String, int> tripCounts = {};
        Map<String, Map<String, dynamic>> tripDetails = {};

        if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
          final docs = snapshot.data!.docs.toList();
          
          docs.sort((a, b) {
            final tA = ((a.data() as Map)['booking_time'] as Timestamp?)?.toDate() ?? DateTime.now();
            final tB = ((b.data() as Map)['booking_time'] as Timestamp?)?.toDate() ?? DateTime.now();
            return tB.compareTo(tA); 
          });

          for (var doc in docs) {
            final data = doc.data() as Map<String, dynamic>;
            
            if (data['type'] == 'ondemand' && ['pending', 'searching', 'admin_review', 'confirmed', 'arriving', 'on_board', 'onboard', 'expired'].contains(data['status'])) {
              hasActiveOnDemand = true;
              activeDoc = doc;
            }

            if (data['status'] == 'completed') {
              final pId = data['pickup_stop_id'];
              final pName = data['pickup_stop_name'];
              final dId = data['dropoff_stop_id'];
              final dName = data['dropoff_stop_name'];

              if (pId != null && dId != null && pId != dId) {
                String key = "${pId}::${dId}";
                tripCounts[key] = (tripCounts[key] ?? 0) + 1;
                if (!tripDetails.containsKey(key)) {
                  tripDetails[key] = {
                    'pId': pId,
                    'pName': pName,
                    'dId': dId,
                    'dName': dName,
                  };
                }
              }
            }
          }
        }

        var sortedTripKeys = tripCounts.keys.toList()..sort((a, b) => tripCounts[b]!.compareTo(tripCounts[a]!));
        List<Map<String, dynamic>> frequentTrips = sortedTripKeys.map((key) => tripDetails[key]!).toList();

        if (hasActiveOnDemand && activeDoc != null) {
          final data = activeDoc.data() as Map<String, dynamic>;
          final status = data['status'];

          if (status == 'expired') return _buildTimeoutCard(data, activeDoc);

          if (status == 'pending' || status == 'searching' || status == 'admin_review') {
            final reqTime = (data['request_time'] as Timestamp?)?.toDate() ?? DateTime.now();
            final elapsed = DateTime.now().difference(reqTime);
            
            if (elapsed > const Duration(minutes: 5)) {
              WidgetsBinding.instance.addPostFrameCallback((_) => _handleTimeoutAndRefund(activeDoc!));
              return const Center(child: CircularProgressIndicator()); 
            } else {
              if (status == 'admin_review') {
                return _buildActiveTripBlocker("Hold On Tight", "Drivers are currently busy. An admin is manually finding a shuttle for you.");
              } else {
                return _buildActiveTripBlocker("Searching for Driver", "We are pinging available shuttles. Check the Tracking page for live updates.");
              }
            }
          } 
          
          if (['confirmed', 'arriving', 'on_board', 'onboard'].contains(status)) {
            return _buildActiveTripBlocker("On-Demand Trip in Progress", "You have an ongoing on-demand trip. Please complete it before requesting another.");
          }
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
          child: Column(
            children: [
              Row(
                children: [
                  Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFFEA580C).withOpacity(0.1), shape: BoxShape.circle), child: const Icon(Icons.hail_rounded, color: Color(0xFFEA580C), size: 28)),
                  const SizedBox(width: 16),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("Request a Ride", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.5)), Text("Immediate shuttle service to your destination.", style: TextStyle(color: Colors.grey.shade600, fontSize: 13))])),
                ],
              ),
              const SizedBox(height: 24),
              StreamBuilder<QuerySnapshot>(
                stream: _stopsStream, 
                builder: (context, snapshot) {
                  if (snapshot.hasError) return Text("Error loading stops: ${snapshot.error}");
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Color(0xFF104C97)));

                  final allStops = snapshot.data!.docs;
                  final relevantStops = allStops.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final List<dynamic> zoneIds = data['zone_ids'] ?? [];
                    final String name = (data['name'] ?? '').toString().toLowerCase();
                    return zoneIds.contains(widget.zoneId) || name.contains('miit') || name.contains('main campus');
                  }).toList();
                  
                  if (relevantStops.isEmpty) return const Center(child: Text("No relevant stops found."));

                  final Map<String, String> stopLookup = {for (var doc in relevantStops) doc.id: (doc.data() as Map<String, dynamic>)['name'] ?? 'Unknown Stop'};

                  if (_selectedPickupStopId != null && !stopLookup.containsKey(_selectedPickupStopId)) {
                    _selectedPickupStopId = null;
                    _selectedPickupStopName = null;
                  }
                  if (_selectedDropoffStopId != null && !stopLookup.containsKey(_selectedDropoffStopId)) {
                    _selectedDropoffStopId = null;
                    _selectedDropoffStopName = null;
                  }

                  List<Map<String, dynamic>> validFrequentTrips = frequentTrips.where((trip) {
                    return stopLookup.containsKey(trip['pId']) && stopLookup.containsKey(trip['dId']);
                  }).take(3).toList(); 

                  final dropdownItems = relevantStops.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final bool isCampus = data['name'].toString().toLowerCase().contains('miit');
                    return DropdownMenuItem(
                      value: doc.id,
                      child: Row(
                        children: [
                          if (isCampus) const Padding(padding: EdgeInsets.only(right: 8.0), child: Icon(Icons.school, color: Color(0xFF262562), size: 16)),
                          Expanded(child: Text(data['name'] ?? 'Unknown Stop', overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: isCampus ? FontWeight.bold : FontWeight.w600))),
                        ],
                      ),
                    );
                  }).toList();

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (validFrequentTrips.isNotEmpty) ...[
                        const Row(
                          children: [
                            Icon(Icons.auto_awesome_rounded, color: Color(0xFFF0AB00), size: 18),
                            SizedBox(width: 8),
                            Text("Frequent Routes", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          clipBehavior: Clip.none,
                          child: Row(
                            children: validFrequentTrips.map((trip) {
                              
                              String pNameSafe = stopLookup[trip['pId']] ?? trip['pName']?.toString() ?? 'Stop';
                              String dNameSafe = stopLookup[trip['dId']] ?? trip['dName']?.toString() ?? 'Stop';

                              return GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _selectedPickupStopId = trip['pId'];
                                    _selectedPickupStopName = stopLookup[trip['pId']];
                                    _selectedDropoffStopId = trip['dId'];
                                    _selectedDropoffStopName = stopLookup[trip['dId']];
                                  });
                                  _showFloatingSnackBar("Frequent route applied!", color: Colors.green);
                                },
                                child: Container(
                                  margin: const EdgeInsets.only(right: 12),
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: Colors.grey.shade200),
                                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 6, offset: const Offset(0, 3))],
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.history_rounded, size: 16, color: Color(0xFF262562)),
                                      const SizedBox(width: 8),
                                      Text(
                                        "${pNameSafe.split(' ').first} → ${dNameSafe.split(' ').first}", 
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF262562))
                                      ),
                                    ]
                                  )
                                )
                              );
                            }).toList(),
                          )
                        ),
                        const SizedBox(height: 24),
                      ],

                      Container(
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 15, offset: const Offset(0, 5))], border: Border.all(color: Colors.grey.shade100)),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        child: Row(
                          children: [
                            Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.circle, color: Colors.green, size: 16), Container(width: 2, height: 40, margin: const EdgeInsets.symmetric(vertical: 4), color: Colors.grey.shade300), const Icon(Icons.square, color: Colors.redAccent, size: 16)]),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildCleanDropdown(
                                    hint: "Pickup Location", value: _selectedPickupStopId, items: dropdownItems,
                                    onChanged: (val) {
                                      setState(() {
                                        _selectedPickupStopId = val;
                                        _selectedPickupStopName = stopLookup[val];
                                        if (_selectedDropoffStopId == val) { _selectedDropoffStopId = null; _selectedDropoffStopName = null; }
                                      });
                                    }
                                  ),
                                  Divider(height: 1, thickness: 1, color: Colors.grey.shade200),
                                  _buildCleanDropdown(
                                    hint: "Dropoff Location", value: _selectedDropoffStopId, items: dropdownItems,
                                    onChanged: (val) {
                                      setState(() {
                                        _selectedDropoffStopId = val;
                                        _selectedDropoffStopName = stopLookup[val];
                                        if (_selectedPickupStopId == val) { _selectedPickupStopId = null; _selectedPickupStopName = null; }
                                      });
                                    }
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            GestureDetector(
                              onTap: _flipLocations,
                              child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.grey.shade50, shape: BoxShape.circle, border: Border.all(color: Colors.grey.shade200)), child: const Icon(Icons.swap_vert_rounded, color: Color(0xFF262562))),
                            )
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 60,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _requestRide,
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF262562), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), elevation: 8, shadowColor: const Color(0xFF262562).withOpacity(0.5)),
                  child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text("Request Shuttle", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                ),
              ),
              const SizedBox(height: 120), 
            ],
          ),
        );
      },
    );
  }

  Widget _buildActiveTripBlocker(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(32), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 10))]),
        child: Column(
          children: [
            Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: const Color(0xFFEA580C).withOpacity(0.1), shape: BoxShape.circle), child: const Icon(Icons.hail_rounded, color: Color(0xFFEA580C), size: 48)),
            const SizedBox(height: 24),
            Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.5), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Text(subtitle, style: TextStyle(color: Colors.grey.shade600, fontSize: 14, height: 1.5), textAlign: TextAlign.center),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context, 'goToTracking'), 
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF262562), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), elevation: 0),
                child: const Text("View Tracking", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildTimeoutCard(Map<String, dynamic> data, DocumentSnapshot doc) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28), border: Border.all(color: Colors.red.shade100, width: 2), boxShadow: [BoxShadow(color: Colors.red.withOpacity(0.05), blurRadius: 25, offset: const Offset(0, 10))]),
        child: Column(
          children: [
            Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.red.shade50, shape: BoxShape.circle), child: const Icon(Icons.timer_off_rounded, color: Colors.redAccent, size: 40)),
            const SizedBox(height: 16),
            const Text("Request Timed Out", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
            const SizedBox(height: 8),
            Text("No drivers accepted the request. Your RM ${double.tryParse(data['fare']?.toString() ?? '2.0')?.toStringAsFixed(2)} fare has been fully refunded.", style: TextStyle(color: Colors.grey.shade600, fontSize: 14), textAlign: TextAlign.center),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: _isLoading 
                ? const Center(child: CircularProgressIndicator())
                : ElevatedButton(
                    onPressed: () async {
                      setState(() => _isLoading = true);
                      try {
                        await FirebaseFirestore.instance.runTransaction((tx) async {
                          final studentRef = FirebaseFirestore.instance.collection('Students').doc(user!.uid);
                          final studentSnap = await tx.get(studentRef);
                          final balance = (studentSnap.data()?['balance'] ?? 0.0).toDouble();
                          final fare = (data['fare'] ?? 2.0).toDouble();
                          
                          if (balance < fare) throw Exception("Insufficient Campus Credits. Please top up.");
                          
                          tx.update(studentRef, {'balance': balance - fare});
                          
                          tx.update(doc.reference, {
                            'status': 'searching',
                            'request_time': FieldValue.serverTimestamp(),
                            'booking_time': FieldValue.serverTimestamp(),
                          });
                          
                          final txnRef = FirebaseFirestore.instance.collection('Transactions').doc();
                          tx.set(txnRef, {
                            'user_id': user!.uid,
                            'type': 'debit',
                            'amount': fare,
                            'description': 'On-Demand Request (Resend)',
                            'reference_id': doc.id,
                            'timestamp': FieldValue.serverTimestamp(),
                          });
                        });
                        if (mounted) _showFloatingSnackBar("Request sent! RM ${data['fare'] ?? '2.00'} deducted.", color: Colors.green);
                      } catch (e) {
                        _showFloatingSnackBar(e.toString());
                      } finally {
                        if (mounted) setState(() => _isLoading = false);
                      }
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF262562), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                    child: const Text("Resend Request", style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () {
                doc.reference.update({'status': 'expired_acknowledged'});
              }, 
              child: const Text("Dismiss & Book New", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))
            )
          ],
        ),
      ),
    );
  }

  Widget _buildCleanDropdown({required String hint, required String? value, required List<DropdownMenuItem<String>> items, required Function(String?) onChanged}) {
    return DropdownButtonFormField<String>(
      value: value,
      isExpanded: true,
      icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey),
      decoration: InputDecoration(hintText: hint, hintStyle: TextStyle(color: Colors.grey.shade400, fontWeight: FontWeight.w600), border: InputBorder.none, isDense: true, contentPadding: const EdgeInsets.symmetric(vertical: 16)),
      items: items,
      onChanged: onChanged,
    );
  }
}