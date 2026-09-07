import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:campuspulse/modules/tracking/map_widget.dart';
import 'package:campuspulse/modules/booking/booking_page.dart';
import 'package:campuspulse/modules/rating/rating_page.dart'; 
import 'package:http/http.dart' as http; 
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart'; 
import 'package:flutter_dotenv/flutter_dotenv.dart'; 

class TrackingPage extends StatefulWidget {
  const TrackingPage({super.key});

  @override
  State<TrackingPage> createState() => _TrackingPageState();
}

class _TrackingPageState extends State<TrackingPage> {
  final User? user = FirebaseAuth.instance.currentUser;
  final String _googleMapsApiKey = dotenv.env['GOOGLE_MAPS_API_KEY'] ?? ""; 

  static const LatLng _uniKLLocation = LatLng(3.1592, 101.7019);

  Set<Marker> _baseMarkers = {}; 
  Set<Polyline> _polylines = {};
  Set<Polygon> _polygons = {}; 
  
  final Map<String, LatLng> _stopCoordinates = {};
  final Map<String, String> _stopNames = {};
  final Map<String, List<String>> _routePaths = {};
  final Map<String, Map<String, String>> _routeMeta = {};
  
  String? _currentPolylineId; 
  String _studentName = "Student";

  bool _isCardMinimized = false;
  bool _isRefunding = false;
  String? _trackedActiveBookingId; 
  
  // --- THE FIX: Added Refresh State ---
  bool _isRefreshing = false;

  int _focusedCardIndex = 0;

  BitmapDescriptor? _onlineBusIcon;
  BitmapDescriptor? _offlineBusIcon;

  Timer? _timeoutTimer;

  @override
  void initState() {
    super.initState();
    _createCustomMarkers();
    _loadStops();
    _loadRoutes();
    _fetchStudentName();
    
    _timeoutTimer = Timer.periodic(const Duration(seconds: 15), (_) => _checkScheduledTimeouts());
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    super.dispose();
  }

  // --- THE FIX: Dedicated Refresh Handler for the Tracking Page ---
  Future<void> _handleRefresh() async {
    setState(() => _isRefreshing = true);
    try {
      await Future.wait([
        _loadStops(),
        _loadRoutes(),
        _fetchStudentName(),
        // Small delay ensures the spinner shows for a smooth UX while streams auto-update
        Future.delayed(const Duration(milliseconds: 800)), 
      ]);
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  void _checkScheduledTimeouts() {
    if (_trackedActiveBookingId == null) return;
    FirebaseFirestore.instance.collection('Bookings').doc(_trackedActiveBookingId).get().then((doc) async {
      if (!doc.exists) return;
      final data = doc.data() as Map<String, dynamic>;
      
      if (data['type'] == 'scheduled') {
         final departureTime = _getDateTime(data);
         final diff = DateTime.now().difference(departureTime).inMinutes;
         
         if (data['status'] == 'confirmed' || data['status'] == 'arriving' || data['status'] == 'arrived') {
            bool isNoShow = false;
            bool triggerTimeout = false;
            
            if (data['schedule_id'] != null) {
              final sDoc = await FirebaseFirestore.instance.collection('Schedules').doc(data['schedule_id']).get();
              if (sDoc.exists) {
                final sData = sDoc.data() as Map<String, dynamic>;
                final sStatus = sData['status'];

                // --- THE FIX: Backend schedule synchronization ---
                if (sStatus == 'missed' || sStatus == 'cancelled') {
                  triggerTimeout = true;
                  isNoShow = false; // Driver missed/cancelled. Refund user.
                } else if (sStatus == 'active' || sStatus == 'completed') {
                  final logs = sData['trip_logs'] as List<dynamic>?;
                  if (logs != null) {
                    final pickupName = data['pickup_stop_name'] ?? '';
                    bool hasArrived = false;
                    bool hasDeparted = false;

                    // --- THE FIX: Chronological log reading to catch departure after arrival ---
                    for (var log in logs) {
                      final msg = log['message']?.toString() ?? '';
                      if (msg.contains("Arrived at <b>$pickupName</b>") || msg.contains("Arrived at $pickupName") || msg.contains("Arrived at Pickup")) {
                        hasArrived = true;
                      } else if (hasArrived && (msg.contains("Departed") || msg.contains("Navigation") || msg.contains("Arrived at "))) {
                        hasDeparted = true;
                      }
                    }

                    if (hasArrived && hasDeparted) {
                      triggerTimeout = true;
                      isNoShow = true; // Driver arrived and subsequently departed.
                    } else if (diff >= 15 && !hasArrived) {
                      triggerTimeout = true;
                      isNoShow = false; // Driver never arrived.
                    } else if (diff >= 15 && hasArrived && !hasDeparted) {
                      triggerTimeout = true;
                      isNoShow = true; // Driver arrived, but 15 min buffer exhausted.
                    }
                  }
                }
              }
            }

            if (!triggerTimeout && diff >= 15 && data['schedule_id'] == null) {
               triggerTimeout = true;
               isNoShow = false; // Fallback
            }

            if (triggerTimeout) {
               _timeoutScheduledBooking(doc, isNoShow: isNoShow);
            }
         }
      }
    });
  }

  Future<void> _timeoutScheduledBooking(DocumentSnapshot doc, {required bool isNoShow}) async {
    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final freshDoc = await tx.get(doc.reference);
        final data = freshDoc.data() as Map<String, dynamic>;
        
        if (data['status'] == 'expired' || data['status'] == 'cancelled' || data['status'] == 'completed' || data['status'] == 'missed') return; 
        
        final studentRef = FirebaseFirestore.instance.collection('Students').doc(user!.uid);
        final studentSnap = await tx.get(studentRef);
        
        DocumentSnapshot? scheduleSnap;
        if (data['schedule_id'] != null) {
          final scheduleRef = FirebaseFirestore.instance.collection('Schedules').doc(data['schedule_id']);
          scheduleSnap = await tx.get(scheduleRef);
        }

        final fare = double.tryParse(data['fare']?.toString() ?? '2.0') ?? 2.0;

        tx.update(doc.reference, {
          'status': 'expired',
          'is_no_show': isNoShow, 
        });

        if (!isNoShow) {
          if (studentSnap.exists) {
            final currentBalance = (studentSnap.data()?['balance'] ?? 0.0).toDouble();
            tx.update(studentRef, {'balance': currentBalance + fare});
          }

          final txnRef = FirebaseFirestore.instance.collection('Transactions').doc();
          tx.set(txnRef, {
            'user_id': user!.uid,
            'type': 'credit',
            'amount': fare,
            'description': 'Refund: Shuttle Did Not Arrive',
            'reference_id': doc.id,
            'timestamp': FieldValue.serverTimestamp(),
          });
        }

        if (scheduleSnap != null && scheduleSnap.exists) {
          final int bookedCount = (scheduleSnap.data() as Map<String, dynamic>?)?['booked_count'] ?? 1;
          tx.update(scheduleSnap.reference, {'booked_count': (bookedCount - 1).clamp(0, 999)});
        }

      });
    } catch (e) {
      debugPrint("Scheduled Timeout refund failed: $e");
    }
  }

  Future<void> _timeoutAndRefundBooking(DocumentSnapshot doc) async {
    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final freshDoc = await tx.get(doc.reference);
        final data = freshDoc.data() as Map<String, dynamic>;
        
        if (data['status'] != 'pending' && data['status'] != 'searching' && data['status'] != 'admin_review') return; 
        
        final studentRef = FirebaseFirestore.instance.collection('Students').doc(user!.uid);
        final studentSnap = await tx.get(studentRef);
        
        final fare = double.tryParse(data['fare']?.toString() ?? '2.0') ?? 2.0;

        tx.update(doc.reference, {'status': 'expired'});

        if (studentSnap.exists) {
          final currentBalance = (studentSnap.data()?['balance'] ?? 0.0).toDouble();
          tx.update(studentRef, {'balance': currentBalance + fare});
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
      debugPrint("Timeout refund failed: $e");
    }
  }

  Future<void> _createCustomMarkers() async {
    try {
      final online = await _getCustomBusMarker(const Color(0xFF104C97)); 
      final offline = await _getCustomBusMarker(Colors.orange);         
      
      if (mounted) {
        setState(() {
          _onlineBusIcon = online;
          _offlineBusIcon = offline;
        });
      }
    } catch (e) { debugPrint("Failed to create custom marker: $e"); }
  }

  Future<BitmapDescriptor> _getCustomBusMarker(Color bgColor) async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);
    const double size = 40.0; 

    final Paint paint = Paint()..color = bgColor;
    canvas.drawCircle(const Offset(size / 2, size / 2), size / 2, paint);

    final Paint borderPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3.0 
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(const Offset(size / 2, size / 2), size / 2, borderPaint);

    TextPainter textPainter = TextPainter(textDirection: ui.TextDirection.ltr);
    textPainter.text = TextSpan(
      text: String.fromCharCode(Icons.directions_bus.codePoint),
      style: TextStyle(
        fontSize: 20.0, 
        fontFamily: Icons.directions_bus.fontFamily,
        package: Icons.directions_bus.fontPackage,
        color: Colors.white,
      ),
    );
    textPainter.layout();
    textPainter.paint(
      canvas, 
      Offset((size - textPainter.width) / 2, (size - textPainter.height) / 2)
    );

    final ui.Image image = await pictureRecorder.endRecording().toImage(size.toInt(), size.toInt());
    final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(byteData!.buffer.asUint8List());
  }

  Future<void> _fetchStudentName() async {
    if (user == null) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('Students').doc(user!.uid).get();
      if (doc.exists && mounted) setState(() { _studentName = doc.data()?['full_name'] ?? doc.data()?['username'] ?? "Student"; });
    } catch (e) { debugPrint("Error fetching name: $e"); }
  }

  String _formatTimeRaw(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return "--:--";
    try {
      final parts = timeStr.split(':');
      final dt = DateTime(2000, 1, 1, int.parse(parts[0]), int.parse(parts[1]));
      return DateFormat('hh:mm a').format(dt);
    } catch (_) {
      return timeStr;
    }
  }

  Map<String, dynamic> _getDynamicNextStopAndETA(Map<String, dynamic> bData, bool isOnBoard, DocumentSnapshot? scheduleDoc) {
    String nextStop = isOnBoard 
        ? (bData['dropoff_stop_name'] ?? 'Destination') 
        : (bData['pickup_stop_name'] ?? 'Pickup Location');
        
    String liveEtaDisplay = '';

    if (bData['type'] == 'scheduled' && scheduleDoc != null && scheduleDoc.exists) {
      final sData = scheduleDoc.data() as Map<String, dynamic>;
      liveEtaDisplay = sData['live_eta'] ?? ''; 
      
      // --- THE FIX: Fetch dynamic next stop based on actual route progress ---
      if (isOnBoard) {
        final logs = sData['trip_logs'] as List<dynamic>?;
        if (logs != null && logs.isNotEmpty) {
          String? lastVisitedName;
          for (var log in logs.reversed) {
            String msg = log['message']?.toString() ?? '';
            if (msg.contains("Arrived at <b>")) {
              final match = RegExp(r'<b>(.*?)</b>').firstMatch(msg);
              if (match != null) {
                lastVisitedName = match.group(1);
                break;
              }
            } else if (msg.contains("Arrived at ")) {
              lastVisitedName = msg.split("Arrived at ").last.trim();
              break;
            }
          }

          if (lastVisitedName != null) {
            final routeId = bData['route_id'];
            if (routeId != null && _routePaths.containsKey(routeId)) {
              final path = _routePaths[routeId]!;
              int lastIndex = path.indexWhere((id) => _stopNames[id] == lastVisitedName);
              if (lastIndex != -1 && lastIndex < path.length - 1) {
                nextStop = _stopNames[path[lastIndex + 1]] ?? nextStop;
              }
            }
          }
        }
      }
    } 
    else if (bData['type'] == 'ondemand') {
      liveEtaDisplay = bData['live_eta'] ?? '';
    }

    return {
      'nextStop': nextStop,
      'liveEta': liveEtaDisplay,
    };
  }

  Future<void> _loadStops() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('Stops').where('status', isEqualTo: 'active').get();
      final Set<Marker> newMarkers = {};
      final Map<String, List<LatLng>> zonePoints = {};
      
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final stopId = data['stop_id'] ?? doc.id;
        final pos = LatLng((data['lat'] as num?)?.toDouble() ?? 0.0, (data['lng'] as num?)?.toDouble() ?? 0.0);
        _stopCoordinates[stopId] = pos;
        _stopNames[stopId] = data['name'] ?? 'Stop';

        newMarkers.add(Marker(
          markerId: MarkerId(stopId),
          position: pos,
          infoWindow: InfoWindow(title: _stopNames[stopId]),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        ));

        final zoneIds = data['zone_ids'];
        if (zoneIds is List && zoneIds.isNotEmpty) zonePoints.putIfAbsent(zoneIds[0].toString(), () => []).add(pos);
      }

      Set<Polygon> newPolys = {};
      zonePoints.forEach((zId, pts) {
        if (pts.length >= 3) {
          newPolys.add(Polygon(
            polygonId: PolygonId('zone_$zId'),
            points: _getConvexHull(pts),
            strokeWidth: 2,
            strokeColor: Colors.blue.withOpacity(0.3),
            fillColor: Colors.blue.withOpacity(0.08),
          ));
        }
      });

      if (mounted) setState(() { _baseMarkers = newMarkers; _polygons = newPolys; });
    } catch (e) { debugPrint("Stop load error: $e"); }
  }

  Future<void> _loadRoutes() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('Routes').where('status', isEqualTo: 'active').get();
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final String rId = data['route_id'] ?? doc.id;
        final List<dynamic> stops = data['stop_ids'] ?? [];
        List<String> path = stops.map((s) => s is Map ? s['stop_id'].toString() : s.toString()).toList();
        
        _routePaths[rId] = path;
        _routeMeta[rId] = { 'start': data['start_stop_id']?.toString() ?? '', 'end': data['end_stop_id']?.toString() ?? '' };
      }
      if (mounted) setState(() {});
    } catch (e) { debugPrint("Route load error: $e"); }
  }

  List<LatLng> _getConvexHull(List<LatLng> points) {
    if (points.length < 3) return points;
    List<LatLng> sorted = List.from(points)..sort((a, b) => a.longitude == b.longitude ? a.latitude.compareTo(b.latitude) : a.longitude.compareTo(b.longitude));
    double cross(LatLng o, LatLng a, LatLng b) => (a.longitude - o.longitude) * (b.latitude - o.latitude) - (a.latitude - o.latitude) * (b.longitude - o.longitude);
    List<LatLng> lower = [], upper = [];
    for (var p in sorted) { while (lower.length >= 2 && cross(lower[lower.length - 2], lower.last, p) <= 0) lower.removeLast(); lower.add(p); }
    for (var p in sorted.reversed) { while (upper.length >= 2 && cross(upper[upper.length - 2], upper.last, p) <= 0) upper.removeLast(); upper.add(p); }
    return (lower..removeLast()) + (upper..removeLast());
  }

  Set<Marker> _generateActiveMarkers(List<String> activeStopIds, {String? pickupId, String? dropoffId, String? routeStartId, String? routeEndId}) {
    Map<String, Marker> markerMap = { for (var m in _baseMarkers) m.markerId.value: m };
    for (int i = 0; i < activeStopIds.length; i++) {
      String id = activeStopIds[i];
      if (!_stopCoordinates.containsKey(id)) continue;
      double hue = BitmapDescriptor.hueAzure;
      double zIdx = 1.0;
      if (id == pickupId || (pickupId == null && id == routeStartId)) { hue = BitmapDescriptor.hueGreen; zIdx = 3.0; }
      else if (id == dropoffId || (dropoffId == null && id == routeEndId)) { hue = BitmapDescriptor.hueRed; zIdx = 3.0; }
      
      markerMap[id] = Marker(
        markerId: MarkerId(id),
        position: _stopCoordinates[id]!,
        infoWindow: InfoWindow(title: _stopNames[id], snippet: id == pickupId ? "Your Pickup" : "Stop #${i+1}"),
        icon: BitmapDescriptor.defaultMarkerWithHue(hue),
        zIndex: zIdx,
      );
    }
    return markerMap.values.toSet();
  }

  Future<void> _fetchRoadPolyline(List<LatLng> points, String uniqueId) async {
    if (_currentPolylineId == uniqueId && _polylines.isNotEmpty) return;
    if (points.length < 2) return;
    final uri = Uri.parse("https://routes.googleapis.com/directions/v2:computeRoutes");
    final body = {
      "origin": {"location": {"latLng": {"latitude": points.first.latitude, "longitude": points.first.longitude}}},
      "destination": {"location": {"latLng": {"latitude": points.last.latitude, "longitude": points.last.longitude}}},
      "travelMode": "DRIVE",
      "routingPreference": "TRAFFIC_AWARE",
      "intermediates": points.length > 2 ? points.sublist(1, points.length - 1).map((p) => {"location": {"latLng": {"latitude": p.latitude, "longitude": p.longitude}}, "vehicleStopover": true}).toList() : []
    };
    try {
      final res = await http.post(uri, headers: {'Content-Type': 'application/json', 'X-Goog-Api-Key': _googleMapsApiKey, 'X-Goog-FieldMask': 'routes.polyline.encodedPolyline'}, body: json.encode(body));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data['routes'] != null && (data['routes'] as List).isNotEmpty) {
          final pts = _decodePolyline(data['routes'][0]['polyline']['encodedPolyline']);
          if (mounted) setState(() { _currentPolylineId = uniqueId; _polylines = { Polyline(polylineId: const PolylineId("road"), points: pts, color: const Color(0xFF104C97), width: 5) }; });
        }
      }
    } catch (e) { debugPrint("Polyline error: $e"); }
  }

  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> poly = []; int index = 0, len = encoded.length, lat = 0, lng = 0;
    while (index < len) {
      int b, shift = 0, result = 0;
      do { b = encoded.codeUnitAt(index++) - 63; result |= (b & 0x1f) << shift; shift += 5; } while (b >= 0x20);
      lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      shift = 0; result = 0;
      do { b = encoded.codeUnitAt(index++) - 63; result |= (b & 0x1f) << shift; shift += 5; } while (b >= 0x20);
      lng += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      poly.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return poly;
  }

  Future<void> _cancelAndRefundBooking(DocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    final bool isScheduled = data['type'] == 'scheduled';
    final String currentStatus = data['status'] ?? 'pending';
    
    bool isLateCancel = false;
    double fare = double.tryParse(data['fare']?.toString() ?? '2.0') ?? 2.0;
    double refundAmount = fare;

    if (isScheduled && data['departure_time'] != null) {
      final departureTime = _getDateTime(data);
      final diff = departureTime.difference(DateTime.now());
      if (diff.inMinutes <= 15 && diff.inMinutes >= 0) {
        isLateCancel = true;
        refundAmount = fare / 2; // 50% penalty
      }
    } else if (!isScheduled) {
      if (currentStatus == 'confirmed' || currentStatus == 'arriving' || currentStatus == 'arrived') {
        isLateCancel = true;
        refundAmount = fare / 2; // 50% penalty
      }
    }

    String? selectedReason;
    final TextEditingController otherReasonController = TextEditingController();
    String finalReason = "";

    bool confirm = await showDialog(
      context: context, 
      builder: (c) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: const Text("Cancel Ride?", style: TextStyle(fontWeight: FontWeight.bold)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Please select a reason for cancellation:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 8),
                  ...[
                    "Wait time is longer than expected",
                    "Change of plans (Class moved/cancelled)",
                    "Decided to walk or use own transport",
                    "Selected wrong pickup/drop-off point",
                    "Others"
                  ].map((reason) => RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    visualDensity: const VisualDensity(horizontal: VisualDensity.minimumDensity, vertical: VisualDensity.minimumDensity),
                    title: Text(reason, style: const TextStyle(fontSize: 14)),
                    value: reason,
                    groupValue: selectedReason,
                    activeColor: const Color(0xFF104C97),
                    onChanged: (val) => setStateDialog(() => selectedReason = val),
                  )),
                  if (selectedReason == 'Others')
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0, left: 16.0, right: 16.0),
                      child: TextField(
                        controller: otherReasonController,
                        decoration: InputDecoration(
                          hintText: "Enter your reason...",
                          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF104C97))),
                        ),
                        maxLines: 2,
                      ),
                    ),
                  const SizedBox(height: 16),
                  if (isLateCancel) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              isScheduled 
                                ? "Late Cancellation Warning: Cancelling within 15 minutes of departure incurs a 50% penalty fee. You will be refunded RM ${refundAmount.toStringAsFixed(2)}."
                                : "Cancellation Warning: Your driver is already en route. Cancelling now incurs a 50% penalty fee. You will be refunded RM ${refundAmount.toStringAsFixed(2)}.", 
                              style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold)
                            ),
                          )
                        ]
                      )
                    )
                  ] else ...[
                     Text("Your fare of RM ${fare.toStringAsFixed(2)} will be fully refunded.", style: TextStyle(color: Colors.grey.shade700, fontSize: 13))
                  ]
                ]
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("No", style: TextStyle(color: Colors.grey))),
              ElevatedButton(
                onPressed: () {
                  if (selectedReason == null) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please select a cancellation reason."), backgroundColor: Colors.red));
                    return;
                  }
                  if (selectedReason == 'Others' && otherReasonController.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please specify your reason."), backgroundColor: Colors.red));
                    return;
                  }
                  finalReason = selectedReason == 'Others' ? otherReasonController.text.trim() : selectedReason!;
                  Navigator.pop(c, true);
                }, 
                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), 
                child: const Text("Yes, Cancel", style: TextStyle(color: Colors.white))
              ),
            ],
          );
        }
      )
    ) ?? false;
    
    if (!confirm) return;

    setState(() => _isRefunding = true);

    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final freshDoc = await tx.get(doc.reference);
        final freshData = freshDoc.data() as Map<String, dynamic>;
        
        if (freshData['status'] == 'cancelled') throw Exception("Booking is already cancelled.");
        
        final studentRef = FirebaseFirestore.instance.collection('Students').doc(user!.uid);
        final studentSnap = await tx.get(studentRef);
        
        DocumentSnapshot? scheduleSnap;
        if (isScheduled && freshData['schedule_id'] != null) {
          final scheduleRef = FirebaseFirestore.instance.collection('Schedules').doc(freshData['schedule_id']);
          scheduleSnap = await tx.get(scheduleRef);
        }

        tx.update(doc.reference, {
          'status': 'cancelled',
          'cancellation_reason': finalReason,
          'cancelled_at': FieldValue.serverTimestamp(),
        });

        if (studentSnap.exists) {
          final currentBalance = (studentSnap.data()?['balance'] ?? 0.0).toDouble();
          tx.update(studentRef, {'balance': currentBalance + refundAmount});
        }

        if (scheduleSnap != null && scheduleSnap.exists) {
          final int bookedCount = (scheduleSnap.data() as Map<String, dynamic>?)?['booked_count'] ?? 1;
          tx.update(scheduleSnap.reference, {'booked_count': (bookedCount - 1).clamp(0, 999)});
        }

        final txnRef = FirebaseFirestore.instance.collection('Transactions').doc();
        tx.set(txnRef, {
          'user_id': user!.uid,
          'type': 'credit',
          'amount': refundAmount,
          'description': isLateCancel ? 'Refund (Penalty Applied): Trip' : 'Refund: Cancelled Trip',
          'reference_id': doc.id,
          'timestamp': FieldValue.serverTimestamp(),
        });
      });

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isLateCancel ? "Booking cancelled. RM ${refundAmount.toStringAsFixed(2)} refunded." : "Cancelled. Fare fully refunded."), backgroundColor: Colors.green, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), margin: const EdgeInsets.all(20)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Cancellation failed: $e"), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating));
    } finally {
      if (mounted) setState(() => _isRefunding = false);
    }
  }

  Future<void> _checkIfCompletedAndShowSummary(String bId) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('Bookings').doc(bId).get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        if (data['status'] == 'completed') {
          if (mounted) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => TripSummaryPage(bookingData: data, bookingId: bId),
                fullscreenDialog: true, 
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint("Error checking ghost completion: $e");
    }
  }

  void _showBookingDetails(Map<String, dynamic> initialData, String bId) {
    String currentStatusTracker = initialData['status'] ?? 'pending';

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: "Dismiss",
      pageBuilder: (ctx, a1, a2) => StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('Bookings').doc(bId).snapshots(),
        builder: (context, snapshot) {
          final data = (snapshot.hasData && snapshot.data!.exists) 
              ? snapshot.data!.data() as Map<String, dynamic> 
              : initialData;

          final currentStatus = data['status'] ?? 'pending';

          if (currentStatusTracker != currentStatus) {
            if ((currentStatusTracker == 'confirmed' || currentStatusTracker == 'arriving' || currentStatusTracker == 'arrived') && 
                (currentStatus == 'onboard' || currentStatus == 'on_board')) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (Navigator.canPop(ctx)) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Ticket scanned! Welcome on board."), backgroundColor: Colors.green, behavior: SnackBarBehavior.floating));
                }
              });
            } else if ((currentStatusTracker == 'onboard' || currentStatusTracker == 'on_board') && 
                       currentStatus == 'completed') {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (Navigator.canPop(ctx)) Navigator.pop(ctx);
              });
            }
            currentStatusTracker = currentStatus;
          }

          String pickup = data['pickup_stop_name'] ?? _stopNames[data['pickup_stop_id']] ?? 'N/A';
          String dropoff = data['dropoff_stop_id'] != null ? (_stopNames[data['dropoff_stop_id']] ?? data['dropoff_stop_id']) : 'N/A';
          if (dropoff == 'N/A' && data['route_id'] != null) {
            final eId = _routeMeta[data['route_id']]?['end'];
            if (eId != null) dropoff = _stopNames[eId] ?? eId;
          }
          if (dropoff == 'N/A') dropoff = "UniKL MIIT (Campus)";

          String qrData = jsonEncode({"bid": bId, "name": _studentName});

          return Center(
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: MediaQuery.of(context).size.width * 0.85,
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(32)),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(color: const Color(0xFF104C97).withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                        child: const Text("BOARDING PASS", style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF104C97), letterSpacing: 2, fontSize: 12)),
                      ),
                      const SizedBox(height: 24),
                      
                      if (data['departure_time'] != null && data['type'] == 'scheduled') ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          decoration: BoxDecoration(
                              color: const Color(0xFF104C97),
                              borderRadius: BorderRadius.circular(20),
                          boxShadow: [BoxShadow(color: const Color(0xFF104C97).withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 5))]
                          ),
                          child: Column(
                              children: [
                                const Text("SCHEDULED PICKUP TIME", style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                                const SizedBox(height: 4),
                                Text(
                                    _formatTimeRaw(data['departure_time']),
                                    style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -1)
                                ),
                              ]
                          )
                        ),
                        const SizedBox(height: 24),
                      ],

                      _buildTimelineItem(pickup, "Pickup Location", true),
                      _buildTimelineItem(dropoff, "Destination", false),
                      const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Divider()),
                      
                      FutureBuilder<DocumentSnapshot>(
                        future: data['driver_id'] != null && data['driver_id'] != 'TBD' 
                            ? FirebaseFirestore.instance.collection('Staffs').doc(data['driver_id']).get() 
                            : null,
                        builder: (context, snap) {
                          String sId = data['shuttle_id'] ?? 'TBD';
                          String dName = data['driver_name']?.toString().split(' ').first ?? 'Assigning...';

                          if (snap.hasData && snap.data!.exists) {
                            final staffData = snap.data!.data() as Map<String, dynamic>;
                            dName = staffData['full_name']?.toString().split(' ').first ?? dName;
                            if (sId == 'TBD' || sId.isEmpty) sId = staffData['assigned_shuttle_id'] ?? 'TBD';
                          }

                          final String dateStr = DateFormat('dd/MM/yyyy').format(_getDateTime(data));

                          return Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(child: _buildInfoSmall(Icons.calendar_today, "Date", dateStr)),
                                  Expanded(child: _buildInfoSmall(Icons.directions_bus_rounded, "Shuttle", sId)),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(child: _buildInfoSmall(Icons.person, "Driver", dName)),
                                  Expanded(child: _buildInfoSmall(Icons.category, "Service", data['type'] == 'scheduled' ? "Scheduled" : "On-Demand")),
                                ],
                              ),
                            ]
                          );
                        }
                      ),
                      
                      const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Divider()),
                      
                      GestureDetector(
                        onTap: () => _showZoomedQR(qrData, bId, currentStatusTracker),
                        child: Column(
                          children: [
                            QrImageView(data: qrData, size: 160, backgroundColor: Colors.white, eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF104C97))),
                            const SizedBox(height: 8),
                            Text(
                              "ID: #${bId.toUpperCase().substring(0, 8)}", 
                              style: const TextStyle(fontFamily: 'Courier', fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 12)
                            ),
                            const SizedBox(height: 4),
                            const Text("Tap to enlarge", style: TextStyle(fontSize: 11, color: Colors.blue, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(width: double.infinity, height: 50, child: ElevatedButton(onPressed: () => Navigator.pop(ctx), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF104C97), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))), child: const Text("Close"))),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
      ),
    );
  }

  void _showZoomedQR(String data, String bId, String initialStatus) {
    String currentStatusTracker = initialStatus;

    showDialog(
      context: context,
      builder: (ctx) => StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('Bookings').doc(bId).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasData && snapshot.data!.exists) {
            final freshData = snapshot.data!.data() as Map<String, dynamic>;
            final currentStatus = freshData['status'] ?? 'pending';

            if (currentStatusTracker != currentStatus) {
              if ((currentStatusTracker == 'confirmed' || currentStatusTracker == 'arriving' || currentStatusTracker == 'arrived') && 
                  (currentStatus == 'onboard' || currentStatus == 'on_board')) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (Navigator.canPop(ctx)) Navigator.pop(ctx);
                });
              } else if ((currentStatusTracker == 'onboard' || currentStatusTracker == 'on_board') && 
                         currentStatus == 'completed') {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (Navigator.canPop(ctx)) Navigator.pop(ctx);
                });
              }
              currentStatusTracker = currentStatus;
            }
          }

          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text("Scan Ticket", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  const SizedBox(height: 20),
                  QrImageView(data: data, size: 280, backgroundColor: Colors.white),
                  const SizedBox(height: 20),
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Close"))
                ],
              ),
            ),
          );
        }
      ),
    );
  }

  Widget _buildInfoSmall(IconData icon, String label, String val) {
    return Row(children: [
      Icon(icon, size: 14, color: Colors.grey),
      const SizedBox(width: 8),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
        Text(val, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
      ])),
    ]);
  }

  Widget _buildTimelineItem(String loc, String label, bool isStart) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(children: [
          Container(width: 12, height: 12, decoration: BoxDecoration(color: isStart ? Colors.green : Colors.redAccent, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2))),
          if (isStart) Container(width: 2, height: 35, color: Colors.black12),
        ]),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(loc, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16), overflow: TextOverflow.ellipsis),
          Text(label, style: TextStyle(color: Colors.grey.shade500, fontSize: 12, fontWeight: FontWeight.w600)),
        ])),
      ],
    );
  }

  void _showZoneSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.only(top: 24.0, bottom: 40.0, left: 24.0, right: 24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 24),
              const Text("Where to?", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF262562), letterSpacing: -0.5)),
              const SizedBox(height: 8),
              const Text("Select a zone to view available schedules.", style: TextStyle(color: Colors.grey, fontSize: 14)),
              const SizedBox(height: 24),
              
              FutureBuilder<QuerySnapshot>(
                future: FirebaseFirestore.instance.collection('Zones').where('status', isEqualTo: 'active').get(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: Color(0xFF104C97)));
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return const Text("No zones available right now.");
                  }

                  final availableZones = snapshot.data!.docs.where((doc) {
                    final name = ((doc.data() as Map<String, dynamic>)['name'] ?? '').toString().toLowerCase();
                    return !name.contains('miit') && !name.contains('main campus');
                  }).toList();

                  if (availableZones.isEmpty) {
                    return const Text("No zones available right now.");
                  }

                  return ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: availableZones.length,
                    itemBuilder: (context, index) {
                      final doc = availableZones[index];
                      final data = doc.data() as Map<String, dynamic>;
                      
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade200)
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                          leading: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(color: const Color(0xFFF0AB00).withOpacity(0.2), shape: BoxShape.circle),
                            child: const Icon(Icons.location_city_rounded, color: Color(0xFFE69B00)),
                          ),
                          title: Text(data['name'] ?? 'Zone', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.grey),
                          onTap: () {
                            Navigator.pop(context); 
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => BookingPage(
                                  zoneId: doc.id,
                                  zoneName: data['name'] ?? 'Booking',
                                )
                              )
                            );
                          },
                        ),
                      );
                    },
                  );
                },
              )
            ],
          ),
        );
      }
    );
  }

  int _getPriority(String status) {
    if (['on_board', 'onboard', 'arriving', 'arrived'].contains(status)) return 0;
    if (status == 'pending' || status == 'searching' || status == 'admin_review') return 1;
    if (status == 'confirmed') return 2;
    if (status == 'expired') return 3;
    return 4;
  }

  DateTime _getDateTime(Map<String, dynamic> data) {
    final dateStr = data['date'];
    final timeStr = data['departure_time'];
    if (dateStr != null && timeStr != null) {
      try {
        final parts = timeStr.split(':');
        final dt = DateTime.parse(dateStr);
        return DateTime(dt.year, dt.month, dt.day, int.parse(parts[0]), int.parse(parts[1]));
      } catch (_) {}
    }
    return (data['booking_time'] as Timestamp?)?.toDate() ?? DateTime.now();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('Bookings').where('user_id', isEqualTo: user?.uid).where('status', whereIn: ['confirmed', 'pending', 'searching', 'admin_review', 'arriving', 'arrived', 'on_board', 'onboard', 'expired']).snapshots(),
        builder: (context, snap) {
          DocumentSnapshot? bestBooking;
          int totalActive = 0;
          
          if (snap.hasData) {
            final docs = snap.data!.docs.toList();
            
            final currentActiveIds = docs.map((d) => d.id).toList();
            if (_trackedActiveBookingId != null && !currentActiveIds.contains(_trackedActiveBookingId)) {
              final idToCheck = _trackedActiveBookingId!;
              _trackedActiveBookingId = null; 
              _checkIfCompletedAndShowSummary(idToCheck);
            }
            
            if (docs.isNotEmpty) {
              docs.sort((a, b) {
                final dataA = a.data() as Map<String, dynamic>;
                final dataB = b.data() as Map<String, dynamic>;
                
                final pA = _getPriority(dataA['status'] ?? '');
                final pB = _getPriority(dataB['status'] ?? '');
                
                if (pA != pB) return pA.compareTo(pB);
                
                final dtA = _getDateTime(dataA);
                final dtB = _getDateTime(dataB);
                
                return dtA.compareTo(dtB);
              });
              
              totalActive = docs.length;
              if (_focusedCardIndex >= totalActive) _focusedCardIndex = 0;
              
              bestBooking = docs[_focusedCardIndex];
              _trackedActiveBookingId = bestBooking.id; 
            }
          }

          return Stack(
            children: [
              _buildMap(bestBooking),
              
              // --- THE FIX: Floating Map Refresh Button ---
              Positioned(
                top: MediaQuery.of(context).padding.top + 16,
                left: 20,
                child: _isRefreshing
                  ? Container(
                      height: 48, width: 48,
                      decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: const Offset(0, 4))]),
                      child: const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(color: Color(0xFF104C97), strokeWidth: 3)),
                    )
                  : GestureDetector(
                      onTap: _handleRefresh,
                      child: Container(
                        height: 48, width: 48,
                        decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: const Offset(0, 4))]),
                        child: const Icon(Icons.refresh_rounded, color: Color(0xFF104C97)),
                      ),
                    ),
              ),

              Positioned(
                left: 0, right: 0, bottom: 90, 
                child: _buildBottomLayer(bestBooking, totalActive)
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMap(DocumentSnapshot? bestBooking) {
    LatLng? target; 
    Set<Marker> markers = _baseMarkers;

    if (bestBooking != null) {
      final bData = bestBooking.data() as Map<String, dynamic>;
      final bId = bestBooking.id;
      final shuttleId = bData['shuttle_id'];
      final status = bData['status'] ?? 'pending';
      final isPending = status == 'pending' || status == 'searching' || status == 'admin_review';
      final bool hasActiveShuttle = shuttleId != null && shuttleId.toString().trim().isNotEmpty && shuttleId != 'TBD';

      Stream<QuerySnapshot>? shuttleStream;
      if (hasActiveShuttle) {
        shuttleStream = FirebaseFirestore.instance.collection('Shuttles').where(FieldPath.documentId, isEqualTo: shuttleId).snapshots();
      } else if (isPending) {
        shuttleStream = FirebaseFirestore.instance.collection('Shuttles').where('is_online', isEqualTo: true).snapshots();
      }

      return StreamBuilder<QuerySnapshot>(
        stream: shuttleStream,
        builder: (context, shuttleSnap) {
          List<LatLng> routePts = [];
          List<String> stopIds = [];

          if (bData['type'] == 'scheduled') {
            stopIds = _routePaths[bData['route_id']] ?? [];
          } else {
            if (bData['pickup_stop_id'] != null) stopIds.add(bData['pickup_stop_id']);
            if (bData['dropoff_stop_id'] != null) stopIds.add(bData['dropoff_stop_id']);
          }

          for (var id in stopIds) { if (_stopCoordinates.containsKey(id)) routePts.add(_stopCoordinates[id]!); }
          
          markers = _generateActiveMarkers(stopIds, pickupId: bData['pickup_stop_id'], dropoffId: bData['dropoff_stop_id'], routeStartId: _routeMeta[bData['route_id']]?['start'], routeEndId: _routeMeta[bData['route_id']]?['end']);

          if (shuttleSnap.hasData) {
            for (var doc in shuttleSnap.data!.docs) {
              final shuttleData = doc.data() as Map<String, dynamic>;
              
              if (shuttleData['current_lat'] != null && shuttleData['current_lng'] != null) {
                final dPos = LatLng((shuttleData['current_lat'] as num).toDouble(), (shuttleData['current_lng'] as num).toDouble());
                final bool isOnline = shuttleData['is_online'] ?? false;
                
                final bool hasCustomIcon = _onlineBusIcon != null && _offlineBusIcon != null;
                final String liveMarkerId = hasCustomIcon ? "bus_custom_${doc.id}_${isOnline ? 'on' : 'off'}" : "bus_default_${doc.id}";
                
                final BitmapDescriptor customBusIcon = isOnline 
                    ? (_onlineBusIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet))
                    : (_offlineBusIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange));

                markers.add(Marker(
                  markerId: MarkerId(liveMarkerId), 
                  position: dPos, 
                  icon: customBusIcon,
                  zIndex: hasActiveShuttle && doc.id == shuttleId ? 10 : 8, 
                  anchor: const Offset(0.5, 0.5), 
                  infoWindow: InfoWindow(title: "Shuttle ${doc.id}", snippet: isOnline ? "Live Location" : "Offline / Last Known Location")
                ));

                if (hasActiveShuttle && doc.id == shuttleId) {
                  target = dPos;
                }
              }
            }
          }
          
          if (!hasActiveShuttle && routePts.isNotEmpty) {
            target = routePts.first; 
          }

          if (routePts.isNotEmpty) { _fetchRoadPolyline(routePts, bId); }
          return MapWidget(markers: markers, polylines: _polylines, polygons: _polygons, initialCenter: _uniKLLocation, targetLocation: target);
        },
      );
    }
    
    return MapWidget(markers: _baseMarkers, polylines: const {}, polygons: _polygons, initialCenter: _uniKLLocation, targetLocation: null);
  }

  Widget _buildBottomLayer(DocumentSnapshot? bestBooking, int totalActive) {
    if (bestBooking == null) return _buildNoRideCard(); 

    final d = bestBooking.data() as Map<String, dynamic>;
    final status = d['status'] ?? 'pending';
    
    Widget cardContent;
    if (status == 'expired') {
      cardContent = _buildTimeoutCard(d, bestBooking);
    } else if (status == 'pending' || status == 'searching' || status == 'admin_review') {
      cardContent = _buildMinimizableWrapper(_buildWaitingRoomCard(d, bestBooking), _buildCompactWaitingRoomCard(d), totalActive);
    } else {
      final isOnBoard = status.toString().contains('onboard') || status.toString().contains('on_board');
      cardContent = _buildMinimizableWrapper(_buildModernActiveRideCard(d, bestBooking, isOnBoard, status), _buildCompactActiveRideCard(d, status), totalActive);
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
      child: KeyedSubtree(
        key: ValueKey(bestBooking.id),
        child: cardContent,
      ),
    );
  }

  Widget _buildMinimizableWrapper(Widget fullContent, Widget compactContent, int totalActive) {
    return GestureDetector(
      onVerticalDragEnd: (details) {
        if (details.primaryVelocity! > 50) { setState(() => _isCardMinimized = true); }
        else if (details.primaryVelocity! < -50) { setState(() => _isCardMinimized = false); }
      },
      onHorizontalDragEnd: (details) {
        if (totalActive <= 1) return;
        if (details.primaryVelocity! < -300) {
          setState(() => _focusedCardIndex = (_focusedCardIndex + 1) % totalActive);
        } else if (details.primaryVelocity! > 300) {
          setState(() => _focusedCardIndex = (_focusedCardIndex - 1 + totalActive) % totalActive);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutQuint,
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white, 
          borderRadius: BorderRadius.circular(28), 
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 25, offset: const Offset(0, 10))]
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(2))),
            
            if (totalActive > 1)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(totalActive, (i) => Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: _focusedCardIndex == i ? 20 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: _focusedCardIndex == i ? const Color(0xFF104C97) : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(4),
                    )
                  )),
                ),
              ),

            SizedBox(height: _isCardMinimized ? 12 : 20),
            AnimatedCrossFade(
              firstChild: fullContent,
              secondChild: compactContent,
              crossFadeState: _isCardMinimized ? CrossFadeState.showSecond : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 300),
              sizeCurve: Curves.easeOutQuint,
            )
          ],
        ),
      ),
    );
  }

  Widget _buildModernActiveRideCard(Map<String, dynamic> d, DocumentSnapshot b, bool isOnBoard, String status) {
    if (d['type'] == 'scheduled' && d['schedule_id'] != null) {
      return StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('Schedules').doc(d['schedule_id']).snapshots(),
        builder: (context, scheduleSnap) {
          return _buildModernActiveRideCardContent(d, b, isOnBoard, status, scheduleSnap.data);
        }
      );
    }
    return _buildModernActiveRideCardContent(d, b, isOnBoard, status, null);
  }

  Widget _buildModernActiveRideCardContent(Map<String, dynamic> d, DocumentSnapshot b, bool isOnBoard, String status, DocumentSnapshot? scheduleDoc) {
    final String dateStr = DateFormat('dd/MM/yyyy').format(_getDateTime(d));
    
    final dynamicInfo = _getDynamicNextStopAndETA(d, isOnBoard, scheduleDoc);
    final String nextStop = dynamicInfo['nextStop'];
    final String liveEta = dynamicInfo['liveEta'];

    String displayStatus = status;
    if (d['type'] == 'scheduled' && scheduleDoc != null && scheduleDoc.exists) {
      final sData = scheduleDoc.data() as Map<String, dynamic>;
      final sStatus = sData['status'];
      
      // --- THE FIX: Fast UI sync for missed/cancelled backend schedules ---
      if (sStatus == 'missed' || sStatus == 'cancelled') {
         WidgetsBinding.instance.addPostFrameCallback((_) {
           _timeoutScheduledBooking(b, isNoShow: false);
         });
         displayStatus = 'expired';
      } else if (sStatus == 'active' && status == 'confirmed') {
        displayStatus = 'arriving';
        final logs = sData['trip_logs'] as List<dynamic>?;
        if (logs != null) {
          final pickupName = d['pickup_stop_name'] ?? '';
          bool hasArrived = false;
          bool hasDeparted = false;

          // --- THE FIX: Chronological loop checking for arrival and subsequent departure ---
          for (var log in logs) {
            final msg = log['message']?.toString() ?? '';
            if (msg.contains("Arrived at <b>$pickupName</b>") || msg.contains("Arrived at $pickupName") || msg.contains("Arrived at Pickup")) {
              hasArrived = true;
            } else if (hasArrived && (msg.contains("Departed") || msg.contains("Navigation") || msg.contains("Arrived at "))) {
              hasDeparted = true;
            }
          }

          if (hasArrived && hasDeparted) {
             // The driver arrived and left.
             WidgetsBinding.instance.addPostFrameCallback((_) {
               _timeoutScheduledBooking(b, isNoShow: true);
             });
             displayStatus = 'expired'; // Instantly flip UI while waiting for Firestore
          } else if (hasArrived) {
             displayStatus = 'arrived';
          }
        }
      }
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            _buildStatusBadge(displayStatus.toString().toUpperCase()),
            const Spacer(),
            Text(d['type'] == 'scheduled' ? "Peak Hour" : "On-Demand", style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.grey, fontSize: 11)),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Container(padding: const EdgeInsets.all(10), decoration: const BoxDecoration(color: Color(0xFF104C97), shape: BoxShape.circle), child: const Icon(Icons.directions_bus, color: Colors.white, size: 20)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // --- THE FIX: Changed label to NEXT STOP for clarity ---
              Text(isOnBoard ? "NEXT STOP" : "PICKUP LOCATION", style: const TextStyle(color: Colors.grey, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
              Text(nextStop, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17), overflow: TextOverflow.ellipsis),
            ])),
            
            if (!isOnBoard)
              _isRefunding 
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator())
                : IconButton(onPressed: () => _cancelAndRefundBooking(b), icon: const Icon(Icons.cancel_outlined, color: Colors.redAccent)),
          ],
        ),
        
        if (liveEta.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(16)),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.green.shade100, shape: BoxShape.circle),
                  child: Icon(isOnBoard ? Icons.flag_rounded : Icons.timer_outlined, color: Colors.green, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isOnBoard ? "Arrival at Destination" : "Arriving at Pickup", 
                        style: const TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold)
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (!isOnBoard && d['type'] == 'scheduled' && d['departure_time'] != null) ...[
                            Text("Sch: ${_formatTimeRaw(d['departure_time'])}", style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w700, fontSize: 14)),
                            const Text(" • ", style: TextStyle(color: Colors.green, fontWeight: FontWeight.w700, fontSize: 14)),
                          ],
                          Text("Live ETA: $liveEta", style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w900, fontSize: 14)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        
        const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider()),
        
        FutureBuilder<DocumentSnapshot>(
          future: d['driver_id'] != null && d['driver_id'] != 'TBD' && d['driver_id'].toString().trim().isNotEmpty 
              ? FirebaseFirestore.instance.collection('Staffs').doc(d['driver_id']).get() 
              : null,
          builder: (context, snap) {
            String sId = d['shuttle_id'] ?? 'TBD';
            if (sId.isEmpty) sId = 'TBD';
            
            String dName = d['driver_name']?.toString().split(' ').first ?? 'Assigning...';
            if (dName.isEmpty || dName == 'TBD') dName = 'Assigning...';

            if (snap.hasData && snap.data!.exists) {
              final staffData = snap.data!.data() as Map<String, dynamic>;
              dName = staffData['full_name']?.toString().split(' ').first ?? dName;
              if (sId == 'TBD') sId = staffData['assigned_shuttle_id'] ?? 'TBD';
            }

            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: _buildSummaryIcon(Icons.calendar_today, dateStr)), 
                Expanded(child: _buildSummaryIcon(Icons.directions_bus_rounded, "$sId")),
                Expanded(child: _buildSummaryIcon(Icons.person, dName)),
              ],
            );
          }
        ),
        
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 45,
          child: OutlinedButton(
            onPressed: () => _showBookingDetails(d, b.id),
            style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF104C97), side: const BorderSide(color: Color(0xFF104C97)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
            child: const Text("View Ticket", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  Widget _buildCompactActiveRideCard(Map<String, dynamic> d, String status) {
    if (d['type'] == 'scheduled' && d['schedule_id'] != null) {
      return StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('Schedules').doc(d['schedule_id']).snapshots(),
        builder: (context, scheduleSnap) {
          return _buildCompactActiveRideCardContent(d, status, scheduleSnap.data);
        }
      );
    }
    return _buildCompactActiveRideCardContent(d, status, null);
  }

  Widget _buildCompactActiveRideCardContent(Map<String, dynamic> d, String status, DocumentSnapshot? scheduleDoc) {
    final isOnBoard = status.contains('on_board') || status.contains('onboard');
    final dynamicInfo = _getDynamicNextStopAndETA(d, isOnBoard, scheduleDoc);
    final String nextStop = dynamicInfo['nextStop'];
    final String liveEta = dynamicInfo['liveEta'];

    String displayStatus = status;
    if (d['type'] == 'scheduled' && scheduleDoc != null && scheduleDoc.exists) {
      final sData = scheduleDoc.data() as Map<String, dynamic>;
      final sStatus = sData['status'];
      
      // --- THE FIX: Fast UI sync for missed/cancelled backend schedules ---
      if (sStatus == 'missed' || sStatus == 'cancelled') {
         WidgetsBinding.instance.addPostFrameCallback((_) {
           _timeoutScheduledBooking(scheduleDoc, isNoShow: false);
         });
         displayStatus = 'expired';
      } else if (sStatus == 'active' && status == 'confirmed') {
        displayStatus = 'arriving';
        final logs = sData['trip_logs'] as List<dynamic>?;
        if (logs != null) {
          final pickupName = d['pickup_stop_name'] ?? '';
          bool hasArrived = false;
          bool hasDeparted = false;

          for (var log in logs) {
            final msg = log['message']?.toString() ?? '';
            if (msg.contains("Arrived at <b>$pickupName</b>") || msg.contains("Arrived at $pickupName") || msg.contains("Arrived at Pickup")) {
              hasArrived = true;
            } else if (hasArrived && (msg.contains("Departed") || msg.contains("Navigation") || msg.contains("Arrived at "))) {
              hasDeparted = true;
            }
          }

          if (hasArrived && hasDeparted) {
             displayStatus = 'expired';
          } else if (hasArrived) {
             displayStatus = 'arrived';
          }
        }
      }
    }

    return Row(
      children: [
        Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: const Color(0xFF104C97).withOpacity(0.1), shape: BoxShape.circle), child: const Icon(Icons.directions_bus, color: Color(0xFF104C97), size: 20)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(liveEta.isNotEmpty ? "Live ETA: $liveEta" : "Next Stop", style: TextStyle(color: liveEta.isNotEmpty ? Colors.green : Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
          Text(nextStop, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15), overflow: TextOverflow.ellipsis),
        ])),
        _buildStatusBadge(displayStatus.toString().toUpperCase()),
      ],
    );
  }

  Widget _buildWaitingRoomCard(Map<String, dynamic> data, DocumentSnapshot doc) {
    final String pickup = data['pickup_stop_name'] ?? 'Unknown Location';
    final String dropoff = data['dropoff_stop_name'] ?? 'Unknown Location';
    final String status = data['status'] ?? 'pending';

    return StreamBuilder<int>(
      stream: Stream.periodic(const Duration(seconds: 1), (i) => i),
      builder: (context, snapshot) {
        final bookingTime = (data['booking_time'] as Timestamp?)?.toDate() ?? DateTime.now();
        final now = DateTime.now();
        final elapsed = now.difference(bookingTime);
        final remaining = const Duration(minutes: 5) - elapsed;

        if (remaining.isNegative) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _timeoutAndRefundBooking(doc);
          });
          return const SizedBox.shrink();
        }

        double progress = elapsed.inSeconds / 300.0;
        progress = progress.clamp(0.0, 1.0);

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(status == 'admin_review' ? "Admin Reviewing Request" : "Searching for a Driver", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
            const SizedBox(height: 8),
            Text(status == 'admin_review' ? "Drivers are busy. An admin is manually assigning your ride." : "We're broadcasting your request to shuttles in the zone.", style: TextStyle(color: Colors.grey.shade600, fontSize: 14), textAlign: TextAlign.center),
            
            const SizedBox(height: 20),
            
            Container(
               padding: const EdgeInsets.all(16),
               decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
               child: Column(
                  children: [
                     Row(
                        children: [
                           const Icon(Icons.circle, color: Colors.green, size: 12),
                           const SizedBox(width: 12),
                           Expanded(child: Text(pickup, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), overflow: TextOverflow.ellipsis)),
                        ]
                     ),
                     Padding(
                        padding: const EdgeInsets.only(left: 5.0, top: 4, bottom: 4),
                        child: Align(alignment: Alignment.centerLeft, child: Container(width: 2, height: 12, color: Colors.grey.shade300)),
                     ),
                     Row(
                        children: [
                           const Icon(Icons.square, color: Colors.redAccent, size: 12),
                           const SizedBox(width: 12),
                           Expanded(child: Text(dropoff, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), overflow: TextOverflow.ellipsis)),
                        ]
                     ),
                  ]
               )
            ),

            const SizedBox(height: 24),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                 Text(status == 'admin_review' ? "Escalated..." : "Searching...", style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF104C97))),
                 Text("${remaining.inMinutes}:${(remaining.inSeconds % 60).toString().padLeft(2, '0')}", style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF104C97), fontSize: 16)),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 30, 
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final vanWidth = 30.0;
                  final position = progress * (width - vanWidth);
                  
                  return Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.centerLeft,
                    children: [
                      Container(height: 8, width: double.infinity, decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(4))),
                      Container(height: 8, width: position + (vanWidth / 2), decoration: BoxDecoration(color: const Color(0xFF104C97).withOpacity(0.5), borderRadius: BorderRadius.circular(4))),
                      Positioned(
                        left: position,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(color: Color(0xFF104C97), shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))]),
                          child: const Icon(Icons.airport_shuttle_rounded, color: Colors.white, size: 16),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: _isRefunding 
                ? const Center(child: CircularProgressIndicator())
                : TextButton(
                    onPressed: () => _cancelAndRefundBooking(doc), 
                    child: const Text("Cancel Request", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                  ),
            )
          ],
        );
      }
    );
  }

  Widget _buildCompactWaitingRoomCard(Map<String, dynamic> data) {
    final String pickup = data['pickup_stop_name'] ?? 'Pickup';
    final String dropoff = data['dropoff_stop_name'] ?? 'Dropoff';
    final String status = data['status'] ?? 'pending';

    return StreamBuilder<int>(
      stream: Stream.periodic(const Duration(seconds: 1), (i) => i),
      builder: (context, snapshot) {
        final bookingTime = (data['booking_time'] as Timestamp?)?.toDate() ?? DateTime.now();
        final elapsed = DateTime.now().difference(bookingTime);
        final remaining = const Duration(minutes: 5) - elapsed;

        double progress = elapsed.inSeconds / 300.0;
        progress = progress.clamp(0.0, 1.0);

        return Column(
           crossAxisAlignment: CrossAxisAlignment.start,
           children: [
             Row(
               children: [
                 const RadarPulse(size: 40.0), 
                 const SizedBox(width: 16),
                 Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                   Text(status == 'admin_review' ? "Assigning Admin..." : "Searching for Driver...", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                   Text("$pickup → $dropoff", style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                 ])),
                 Text("${remaining.inMinutes}:${(remaining.inSeconds % 60).toString().padLeft(2, '0')}", style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF104C97), fontSize: 14)),
               ],
             ),
             const SizedBox(height: 16),
             SizedBox(
               height: 30,
               child: LayoutBuilder(
                 builder: (context, constraints) {
                   final width = constraints.maxWidth;
                   final vanWidth = 24.0;
                   final position = progress * (width - vanWidth);
                   
                   return Stack(
                     clipBehavior: Clip.none,
                     alignment: Alignment.centerLeft,
                     children: [
                       Container(height: 6, width: double.infinity, decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(3))),
                       Container(height: 6, width: position + (vanWidth / 2), decoration: BoxDecoration(color: const Color(0xFF104C97).withOpacity(0.5), borderRadius: BorderRadius.circular(3))),
                       Positioned(
                         left: position,
                         child: Container(
                           padding: const EdgeInsets.all(4),
                           decoration: const BoxDecoration(color: Color(0xFF104C97), shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))]),
                           child: const Icon(Icons.airport_shuttle_rounded, color: Colors.white, size: 12),
                         ),
                       ),
                     ],
                   );
                 },
               ),
             ),
           ]
        );
      }
    );
  }

  Widget _buildSummaryIcon(IconData icon, String text) {
    return Row(children: [
      Icon(icon, size: 12, color: Colors.grey.shade400),
      const SizedBox(width: 4),
      Expanded(child: Text(text, style: TextStyle(color: Colors.grey.shade600, fontSize: 11, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
    ]);
  }

  Widget _buildStatusBadge(String status) {
    Color c = Colors.orange;
    if (status.contains("CONFIRMED")) c = Colors.green;
    if (status.contains("ARRIVING") || status.contains("ARRIVED")) c = Colors.blue;
    if (status.contains("ONBOARD") || status.contains("ON_BOARD")) c = const Color(0xFF104C97);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: c.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.lens, size: 8, color: c),
        const SizedBox(width: 6),
        Text(status, style: TextStyle(color: c, fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 0.5)),
      ]),
    );
  }

  Widget _buildNoRideCard() {
    return GestureDetector(
      onTap: _showZoneSelector, 
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 10))]),
        child: Row(
          children: [
            Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFF104C97).withOpacity(0.1), shape: BoxShape.circle), child: const Icon(Icons.directions_bus_filled_outlined, color: Color(0xFF104C97), size: 30)),
            const SizedBox(width: 18),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text("Ready to Move?", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, letterSpacing: -0.5)),
              const SizedBox(height: 4),
              Row(children: [Text("Book a ride now", style: TextStyle(color: Colors.grey.shade600, fontSize: 14, fontWeight: FontWeight.w600)), const SizedBox(width: 4), Icon(Icons.arrow_forward_rounded, size: 16, color: const Color(0xFF104C97).withOpacity(0.8))]),
            ])),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeoutCard(Map<String, dynamic> data, DocumentSnapshot doc) {
    final bool isScheduled = data['type'] == 'scheduled';
    final bool isNoShow = data['is_no_show'] == true;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28), border: Border.all(color: Colors.red.shade100, width: 2), boxShadow: [BoxShadow(color: Colors.red.withOpacity(0.05), blurRadius: 25, offset: const Offset(0, 10))]),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.red.shade50, shape: BoxShape.circle), child: Icon(isScheduled ? Icons.directions_run : Icons.timer_off_rounded, color: Colors.redAccent, size: 40)),
          const SizedBox(height: 16),
          
          Text(isScheduled ? (isNoShow ? "No-Show Detected" : "Shuttle Missed") : "Request Timed Out", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
          const SizedBox(height: 8),
          
          Text(
            isScheduled 
                ? (isNoShow
                    ? "You did not authenticate and board the shuttle after it arrived. As per the No-Show Policy, your fare is strictly non-refundable."
                    : "The shuttle did not arrive within 15 minutes of the scheduled departure. Your RM ${double.tryParse(data['fare']?.toString() ?? '2.0')?.toStringAsFixed(2)} fare has been fully refunded.")
                : "No drivers accepted the request. Your RM ${double.tryParse(data['fare']?.toString() ?? '2.0')?.toStringAsFixed(2)} fare has been fully refunded.", 
            style: TextStyle(color: Colors.grey.shade600, fontSize: 14), textAlign: TextAlign.center
          ),
          
          const SizedBox(height: 24),
          
          if (isScheduled) ...[
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () async {
                  String resolvedZoneName = data['zone_name'] ?? 'Selected Zone';
                  if (resolvedZoneName == 'Selected Zone' && data['zone_id'] != null) {
                    try {
                      final zoneDoc = await FirebaseFirestore.instance.collection('Zones').doc(data['zone_id']).get();
                      if (zoneDoc.exists) resolvedZoneName = (zoneDoc.data() as Map<String, dynamic>)['name'] ?? 'Selected Zone';
                    } catch (e) { debugPrint("Failed to resolve zone name: $e"); }
                  }
                  if (!mounted) return;
                  
                  // --- THE FIX: Change status to missed ---
                  doc.reference.update({'status': 'missed'});
                  
                  Navigator.push(context, MaterialPageRoute(builder: (_) => BookingPage(zoneId: data['zone_id'] ?? '', zoneName: resolvedZoneName, initialIndex: 0)));
                },
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF104C97), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                child: const Text("Book Next Schedule", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton(
                onPressed: () async {
                  String resolvedZoneName = data['zone_name'] ?? 'Selected Zone';
                  if (resolvedZoneName == 'Selected Zone' && data['zone_id'] != null) {
                    try {
                      final zoneDoc = await FirebaseFirestore.instance.collection('Zones').doc(data['zone_id']).get();
                      if (zoneDoc.exists) resolvedZoneName = (zoneDoc.data() as Map<String, dynamic>)['name'] ?? 'Selected Zone';
                    } catch (e) { debugPrint("Failed to resolve zone name: $e"); }
                  }
                  if (!mounted) return;
                  
                  // --- THE FIX: Change status to missed ---
                  doc.reference.update({'status': 'missed'});
                  
                  Navigator.push(context, MaterialPageRoute(builder: (_) => BookingPage(zoneId: data['zone_id'] ?? '', zoneName: resolvedZoneName, initialIndex: 1)));
                },
                style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF104C97), side: const BorderSide(color: Color(0xFF104C97)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                child: const Text("Book On-Demand", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ] else ...[
            SizedBox(
              width: double.infinity,
              height: 50,
              child: _isRefunding 
                ? const Center(child: CircularProgressIndicator())
                : ElevatedButton(
                    onPressed: () async {
                      setState(() => _isRefunding = true);
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
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Request sent! Fare deducted."), backgroundColor: Colors.green, behavior: SnackBarBehavior.floating));
                      } catch (e) {
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating));
                      } finally {
                        if (mounted) setState(() => _isRefunding = false);
                      }
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF104C97), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                    child: const Text("Resend Request", style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
            ),
          ],
          const SizedBox(height: 12),
          TextButton(
            onPressed: () {
               // --- THE FIX: Change status to missed ---
               doc.reference.update({'status': 'missed'});
            }, 
            child: const Text("Dismiss", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))
          )
        ],
      ),
    );
  }

}

class TripSummaryPage extends StatelessWidget {
  final Map<String, dynamic> bookingData;
  final String bookingId;

  const TripSummaryPage({super.key, required this.bookingData, required this.bookingId});

  @override
  Widget build(BuildContext context) {
    final fare = double.tryParse(bookingData['fare']?.toString() ?? '2.0') ?? 2.0;
    final isScheduled = bookingData['type'] == 'scheduled';
    final bool isRated = bookingData['is_rated'] == true;
    
    String pickup = bookingData['pickup_stop_name'] ?? 'Unknown Location';
    
    String dropoff = bookingData['dropoff_stop_name'] ?? '';
    if (dropoff.isEmpty || dropoff == 'Destination') {
      if (isScheduled && bookingData['route_name'] != null) {
        dropoff = bookingData['route_name']; 
      } else {
        dropoff = 'UniKL MIIT (Campus)';
      }
    }
    
    final timestamp = (bookingData['booking_time'] as Timestamp?)?.toDate() ?? DateTime.now();
    final dateStr = DateFormat('dd/MM/yyyy, hh:mm a').format(timestamp);

    return Scaffold(
      backgroundColor: const Color(0xFF104C97),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 40),
            const Text("Trip Completed", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(dateStr, style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14)),
            const SizedBox(height: 40),
            
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(32, 32, 32, 24),
                decoration: const BoxDecoration(
                  color: Color(0xFFF8F9FA),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
                ),
                child: Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(color: Colors.green.shade50, shape: BoxShape.circle),
                              child: const Icon(Icons.check_circle, color: Colors.green, size: 64),
                            ),
                            const SizedBox(height: 32),
                            const Text("RM", style: TextStyle(color: Colors.grey, fontSize: 16, fontWeight: FontWeight.bold)),
                            Text(fare.toStringAsFixed(2), style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: Colors.black87, letterSpacing: -1)),
                            const Text("Fare Deducted", style: TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.w600)),
                            
                            const Padding(padding: EdgeInsets.symmetric(vertical: 32), child: Divider(height: 1, thickness: 1)),
                            
                            Row(
                              children: [
                                const Icon(Icons.directions_bus, color: Color(0xFF104C97)),
                                const SizedBox(width: 16),
                                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  const Text("Shuttle Service", style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                                  Text(isScheduled ? "Peak Hour Shuttle" : "On-Demand Ride", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                                ])),
                              ],
                            ),
                            const SizedBox(height: 20),
                            
                            FutureBuilder<DocumentSnapshot>(
                              future: bookingData['driver_id'] != null && bookingData['driver_id'] != 'TBD' && bookingData['driver_id'].toString().trim().isNotEmpty 
                                  ? FirebaseFirestore.instance.collection('Staffs').doc(bookingData['driver_id']).get() 
                                  : null,
                              builder: (context, snap) {
                                String dName = bookingData['driver_name']?.toString().split(' ').first ?? 'Driver';
                                if (dName.isEmpty || dName == 'TBD') dName = 'Driver';

                                if (snap.hasData && snap.data!.exists) {
                                  final staffData = snap.data!.data() as Map<String, dynamic>;
                                  dName = staffData['full_name']?.toString().split(' ').first ?? dName;
                                }

                                return Row(
                                  children: [
                                    const Icon(Icons.person, color: Color(0xFF104C97)),
                                    const SizedBox(width: 16),
                                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      const Text("Driver", style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                                      Text(dName, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                                    ])),
                                  ],
                                );
                              }
                            ),
                            
                            const SizedBox(height: 32),
                            
                            Container(
                               padding: const EdgeInsets.all(16),
                               decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
                               child: Column(
                                  children: [
                                     Row(
                                        children: [
                                           const Icon(Icons.circle, color: Colors.green, size: 12),
                                           const SizedBox(width: 12),
                                           Expanded(child: Text(pickup, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), overflow: TextOverflow.ellipsis)),
                                        ]
                                     ),
                                     Padding(
                                        padding: const EdgeInsets.only(left: 5.0, top: 4, bottom: 4),
                                        child: Align(alignment: Alignment.centerLeft, child: Container(width: 2, height: 12, color: Colors.grey.shade300)),
                                     ),
                                     Row(
                                        children: [
                                           const Icon(Icons.square, color: Colors.redAccent, size: 12),
                                           const SizedBox(width: 12),
                                           Expanded(child: Text(dropoff, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), overflow: TextOverflow.ellipsis)),
                                        ]
                                     ),
                                  ]
                               )
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Action Buttons (Rate / Done)
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF104C97),
                              side: const BorderSide(color: Color(0xFF104C97)),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            ),
                            child: const Text("Skip", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          ),
                        ),
                        if (!isRated && bookingData['driver_id'] != null && bookingData['driver_id'] != 'TBD') ...[
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton(
                              onPressed: () async {
                                final result = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => RatingPage(
                                      bookingId: bookingId,
                                      driverId: bookingData['driver_id'],
                                    )
                                  )
                                );
                                if (result == 'rated' && context.mounted) {
                                  Navigator.pop(context);
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFF0AB00),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                elevation: 5,
                                shadowColor: const Color(0xFFF0AB00).withOpacity(0.4),
                              ),
                              child: const Text("Rate Driver", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ]
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RadarPulse extends StatefulWidget {
  final double size;
  const RadarPulse({super.key, this.size = 80.0});

  @override
  State<RadarPulse> createState() => _RadarPulseState();
}

class _RadarPulseState extends State<RadarPulse> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(); 
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double innerSize = widget.size * 0.55; 
    return SizedBox(
      height: widget.size,
      width: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Stack(
            alignment: Alignment.center,
            children: [
              Transform.scale(
                scale: 1.0 + (_controller.value * 0.6), 
                child: Opacity(
                  opacity: 1.0 - _controller.value, 
                  child: Container(width: innerSize, height: innerSize, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFF104C97), width: 2))),
                ),
              ),
              Container(width: innerSize, height: innerSize, decoration: const BoxDecoration(color: Color(0xFF104C97), shape: BoxShape.circle), child: Icon(Icons.radar, color: Colors.white, size: innerSize * 0.5)),
            ],
          );
        },
      ),
    );
  }
}