import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:campuspulse/modules/tracking/map_widget.dart';
import 'package:http/http.dart' as http; 
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart'; 

class TrackingPage extends StatefulWidget {
  const TrackingPage({super.key});

  @override
  State<TrackingPage> createState() => _TrackingPageState();
}

class _TrackingPageState extends State<TrackingPage> {
  final User? user = FirebaseAuth.instance.currentUser;
  
  // YOUR API KEY
  final String _googleMapsApiKey = "AIzaSyBnjGNcxW0UPWgfG8S7OZP2PEra22BzwDg"; 

  static const LatLng _uniKLLocation = LatLng(3.1592, 101.7019);

  Set<Marker> _baseMarkers = {}; 
  Set<Polyline> _polylines = {};
  Set<Polygon> _polygons = {}; 
  
  final Map<String, LatLng> _stopCoordinates = {};
  final Map<String, String> _stopNames = {};
  final Map<String, List<String>> _routePaths = {};
  final Map<String, Map<String, String>> _routeMeta = {};
  
  String? _currentPolylineId; 
  String _studentName = "Student"; // Variable to store student name for QR

  @override
  void initState() {
    super.initState();
    _loadStops();
    _loadRoutes();
    _loadZonePolygons(); 
    _fetchStudentName(); // Fetch name on init
  }

  // --- Fetch Student Name for QR ---
  Future<void> _fetchStudentName() async {
    if (user == null) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('Students').doc(user!.uid).get();
      if (doc.exists) {
        if (mounted) {
          setState(() {
            // Prefer full name, fallback to username or default
            _studentName = doc.data()?['full_name'] ?? doc.data()?['username'] ?? "Student";
          });
        }
      }
    } catch (e) {
      debugPrint("[TRACKING_DEBUG] Error fetching student name: $e");
    }
  }

  // --- IMPROVED: More Accurate & Organic Zone Shapes ---
  void _loadZonePolygons() {
    Set<Polygon> polygons = {};

    // 1. Bangsar / Kerinchi (Hostel JPE/JT Area)
    List<LatLng> bangsarCoords = [
      const LatLng(3.1250, 101.6600),
      const LatLng(3.1260, 101.6700),
      const LatLng(3.1180, 101.6780),
      const LatLng(3.1100, 101.6750),
      const LatLng(3.1080, 101.6650),
      const LatLng(3.1150, 101.6580),
    ];
    polygons.add(Polygon(
      polygonId: const PolygonId('zone_bangsar'),
      points: bangsarCoords,
      strokeWidth: 2,
      strokeColor: Colors.blue.withOpacity(0.4),
      fillColor: Colors.blue.withOpacity(0.1),
    ));

    // 2. Wangsa Maju (Section 2, 4, LRT)
    List<LatLng> wangsaMajuCoords = [
      const LatLng(3.2150, 101.7250),
      const LatLng(3.2180, 101.7450),
      const LatLng(3.2050, 101.7550),
      const LatLng(3.1950, 101.7450),
      const LatLng(3.1980, 101.7280),
    ];
    polygons.add(Polygon(
      polygonId: const PolygonId('zone_wangsa_maju'),
      points: wangsaMajuCoords,
      strokeWidth: 2,
      strokeColor: Colors.green.withOpacity(0.4),
      fillColor: Colors.green.withOpacity(0.1),
    ));

    // 3. Setapak (PV Areas / Danau Kota)
    List<LatLng> setapakCoords = [
      const LatLng(3.2100, 101.7050),
      const LatLng(3.2120, 101.7250),
      const LatLng(3.2000, 101.7300),
      const LatLng(3.1900, 101.7200),
      const LatLng(3.1920, 101.7000),
    ];
    polygons.add(Polygon(
      polygonId: const PolygonId('zone_setapak'),
      points: setapakCoords,
      strokeWidth: 2,
      strokeColor: Colors.orange.withOpacity(0.4),
      fillColor: Colors.orange.withOpacity(0.1),
    ));
    
     // 4. Sentul (UTC / Urban)
    List<LatLng> sentulCoords = [
      const LatLng(3.1950, 101.6850),
      const LatLng(3.1850, 101.7050),
      const LatLng(3.1700, 101.6950),
      const LatLng(3.1750, 101.6750),
    ];
    polygons.add(Polygon(
      polygonId: const PolygonId('zone_sentul'),
      points: sentulCoords,
      strokeWidth: 2,
      strokeColor: Colors.red.withOpacity(0.4),
      fillColor: Colors.red.withOpacity(0.1),
    ));
    
    // 5. Gurney Campus (UniKL MIIT)
    List<LatLng> campusCoords = [
       const LatLng(3.1650, 101.6950),
       const LatLng(3.1680, 101.7050),
       const LatLng(3.1600, 101.7100),
       const LatLng(3.1500, 101.7050),
       const LatLng(3.1520, 101.6900),
    ];
     polygons.add(Polygon(
      polygonId: const PolygonId('zone_campus'),
      points: campusCoords,
      strokeWidth: 2,
      strokeColor: const Color(0xFF104C97).withOpacity(0.5),
      fillColor: const Color(0xFF104C97).withOpacity(0.1),
    ));

    if (mounted) {
      setState(() {
        _polygons = polygons;
      });
    }
  }

  Future<void> _loadStops() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('Stops')
          .where('status', isEqualTo: 'active')
          .get();

      final Set<Marker> newMarkers = {};
      
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final stopId = data['stop_id'] ?? doc.id;
        final String stopName = data['name'] ?? 'Stop';
        final double lat = data['lat'] ?? 0.0;
        final double lng = data['lng'] ?? 0.0;
        final pos = LatLng(lat, lng);

        _stopCoordinates[stopId] = pos;
        _stopNames[stopId] = stopName; 

        newMarkers.add(Marker(
          markerId: MarkerId(stopId),
          position: pos,
          infoWindow: InfoWindow(title: stopName),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        ));
      }

      if (mounted) {
        setState(() {
          _baseMarkers = newMarkers;
        });
      }
    } catch (e) {
      debugPrint("[TRACKING_DEBUG] Error loading stops: $e");
    }
  }

  Future<void> _loadRoutes() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('Routes')
          .where('status', isEqualTo: 'active')
          .get();

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final String routeId = data['route_id'] ?? doc.id;
        final List<dynamic> stops = data['stop_ids'] ?? [];
        
        _routePaths[routeId] = List<String>.from(stops);
        
        _routeMeta[routeId] = {
          'start': data['start_stop_id']?.toString() ?? '',
          'end': data['end_stop_id']?.toString() ?? '',
        };
      }
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint("[TRACKING_DEBUG] Error loading routes: $e");
    }
  }

  Set<Marker> _generateActiveMarkers(List<String> activeStopIds, {String? pickupId, String? dropoffId, String? routeStartId, String? routeEndId}) {
    Map<String, Marker> markerMap = {
      for (var m in _baseMarkers) m.markerId.value: m
    };

    for (int i = 0; i < activeStopIds.length; i++) {
      String stopId = activeStopIds[i];
      if (!_stopCoordinates.containsKey(stopId)) continue;

      LatLng pos = _stopCoordinates[stopId]!;
      String name = _stopNames[stopId] ?? "Stop";
      
      double hue = BitmapDescriptor.hueAzure;
      String snippet = "Stop #${i + 1}";
      double zIndex = 1.0; 

      if (pickupId == null) { 
        if (stopId == routeStartId) {
          hue = BitmapDescriptor.hueGreen; 
          snippet = "Start Point";
          zIndex = 2.0;
        } else if (stopId == routeEndId) {
          hue = BitmapDescriptor.hueRed; 
          snippet = "End Point";
          zIndex = 2.0;
        }
      }
      
      if (stopId == pickupId) {
        hue = BitmapDescriptor.hueGreen;
        snippet = "Your Pickup";
        zIndex = 3.0;
      } else if (stopId == dropoffId) {
        hue = BitmapDescriptor.hueRed;
        snippet = "Your Dropoff";
        zIndex = 3.0;
      }

      markerMap[stopId] = Marker(
        markerId: MarkerId(stopId),
        position: pos,
        infoWindow: InfoWindow(title: name, snippet: snippet),
        icon: BitmapDescriptor.defaultMarkerWithHue(hue),
        zIndex: zIndex,
      );
    }

    return markerMap.values.toSet();
  }

  Future<void> _fetchRoadPolyline(List<LatLng> points, String uniqueId) async {
    if (_currentPolylineId == uniqueId && _polylines.isNotEmpty) return;
    if (points.length < 2) return;

    debugPrint("[TRACKING_DEBUG] Fetching route for Booking: $uniqueId with ${points.length} points.");

    // Fallback Polyline (Straight line)
    final fallbackPolyline = Polyline(
      polylineId: const PolylineId("fallback_route"),
      points: points,
      color: Colors.grey.withOpacity(0.5),
      width: 4,
      patterns: [PatternItem.dash(10), PatternItem.gap(10)],
    );

    if (mounted) {
      setState(() {
        _polylines = {fallbackPolyline};
      });
    }

    final uri = Uri.parse("https://routes.googleapis.com/directions/v2:computeRoutes");
    
    final headers = {
      'Content-Type': 'application/json',
      'X-Goog-Api-Key': _googleMapsApiKey,
      'X-Goog-FieldMask': 'routes.duration,routes.distanceMeters,routes.polyline.encodedPolyline,routes.optimizedIntermediateWaypointIndex', 
    };

    final Map<String, dynamic> body = {
      "origin": {
        "location": {
          "latLng": {
            "latitude": points.first.latitude,
            "longitude": points.first.longitude
          }
        }
      },
      "destination": {
        "location": {
          "latLng": {
            "latitude": points.last.latitude,
            "longitude": points.last.longitude
          }
        }
      },
      "travelMode": "DRIVE",
      "routingPreference": "TRAFFIC_AWARE",
      "computeAlternativeRoutes": false,
      "optimizeWaypointOrder": true, 
    };

    if (points.length > 2) {
      body['intermediates'] = points.sublist(1, points.length - 1).map((p) => {
        "location": {
          "latLng": {
            "latitude": p.latitude,
            "longitude": p.longitude
          }
        },
        "vehicleStopover": true
      }).toList();
    }

    try {
      final response = await http.post(uri, headers: headers, body: json.encode(body));

      debugPrint("[TRACKING_DEBUG] API Status: ${response.statusCode}");

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['routes'] != null && (data['routes'] as List).isNotEmpty) {
          final String encodedPoints = data['routes'][0]['polyline']['encodedPolyline'];
          final List<LatLng> decodedPoints = _decodePolyline(encodedPoints);

          debugPrint("[TRACKING_DEBUG] Route decoded with ${decodedPoints.length} points.");

          if (mounted) {
            setState(() {
              _currentPolylineId = uniqueId;
              _polylines = {
                Polyline(
                  polylineId: const PolylineId("road_route"),
                  points: decodedPoints,
                  color: const Color(0xFF104C97),
                  width: 5,
                )
              };
            });
          }
        } else {
          debugPrint("[TRACKING_DEBUG] No routes found in response.");
        }
      } else {
        debugPrint("[TRACKING_DEBUG] API Error Body: ${response.body}");
      }
    } catch (e) {
      debugPrint("[TRACKING_DEBUG] Exception: $e");
    }
  }

  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> poly = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      poly.add(LatLng((lat / 1E5).toDouble(), (lng / 1E5).toDouble()));
    }
    return poly;
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
        setState(() {
          _polylines = {};
          _currentPolylineId = null;
        });
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Booking cancelled.")));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }

  // --- COMPLETE TRIP LOGIC ---
  Future<void> _completeTrip(DocumentSnapshot doc) async {
    bool confirm = await showDialog(
      context: context, 
      builder: (c) => AlertDialog(
        title: const Text("Complete Trip?"),
        content: const Text("Have you arrived at your destination?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("No")),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true), 
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text("Yes"),
          ),
        ],
      )
    ) ?? false;

    if (confirm) {
      try {
        await doc.reference.update({'status': 'completed'});
        setState(() {
          _polylines = {};
          _currentPolylineId = null;
        });
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Trip completed. History updated.")));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }

  // --- MODERN "Boarding Pass" Pop-up Animation ---
  void _showBookingDetails(Map<String, dynamic> data, String bookingId) {
    String pickupName = data['pickup_stop_id'] ?? 'N/A';
    String dropoffName = data['dropoff_stop_id'] ?? 'N/A';
    
    // --- UPDATED LOGIC: Use Route Start/End for Scheduled Rides ---
    if (data['route_id'] != null && _routeMeta.containsKey(data['route_id'])) {
      final routeId = data['route_id'];
      final startId = _routeMeta[routeId]?['start'];
      final endId = _routeMeta[routeId]?['end'];

      if (pickupName == 'N/A' && startId != null && startId.isNotEmpty) {
        pickupName = startId;
      }
      if (dropoffName == 'N/A' && endId != null && endId.isNotEmpty) {
        dropoffName = endId;
      }
    }

    if (_stopNames.containsKey(pickupName)) pickupName = _stopNames[pickupName]!;
    if (_stopNames.containsKey(dropoffName)) dropoffName = _stopNames[dropoffName]!;
    
    if (dropoffName == 'N/A' && data['destination'] != null) {
      dropoffName = data['destination'];
    }

    // --- GENERATE JSON QR DATA ---
    String qrData = jsonEncode({
      "bid": bookingId,
      "name": _studentName
    });

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: "Dismiss",
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 500),
      pageBuilder: (ctx, anim1, anim2) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: MediaQuery.of(context).size.width * 0.85,
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.85, 
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 20,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(24),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // --- Title & ID ---
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Boarding Pass", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xFF104C97))),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFF104C97).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            "#${bookingId.substring(0, 6).toUpperCase()}", // Short ID
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF104C97)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 30),

                    // --- Route Visualization (Timeline) ---
                    _buildTimelineRow(
                      time: data['departure_time'] ?? (data['request_time'] != null ? _formatDate(data['request_time']) : "--:--"),
                      location: pickupName,
                      isStart: true,
                    ),
                    _buildTimelineRow(
                      time: "--:--", 
                      location: dropoffName,
                      isStart: false,
                    ),

                    const SizedBox(height: 30),
                    const Divider(),
                    const SizedBox(height: 30),

                    // --- Info Grid ---
                    Row(
                      children: [
                        Expanded(child: _buildModernDetailItem(Icons.calendar_today, "Date", data['date'] ?? "Today")),
                        Expanded(child: _buildModernDetailItem(Icons.directions_bus, "Shuttle", data['shuttle_id'] ?? "Assigning...")),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(child: _buildModernDetailItem(Icons.person, "Driver", data['driver_name'] ?? "TBD")),
                        Expanded(child: _buildModernDetailItem(Icons.category, "Service", (data['type'] ?? 'Standard').toString().toUpperCase())),
                      ],
                    ),

                    const SizedBox(height: 30),
                    
                    // --- INTERACTIVE REAL QR CODE ---
                    GestureDetector(
                      onTap: () {
                        // ZOOMED QR DIALOG
                        showDialog(
                          context: context,
                          builder: (ctx) => Dialog(
                            backgroundColor: Colors.transparent,
                            insetPadding: const EdgeInsets.all(20),
                            child: Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    decoration: BoxDecoration(
                                      border: Border.all(color: Colors.black12),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    padding: const EdgeInsets.all(10),
                                    child: QrImageView(
                                      data: qrData, // Use JSON string here
                                      version: QrVersions.auto,
                                      size: 300.0,
                                      backgroundColor: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  const Text(
                                    "Scan to Board",
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22, color: Color(0xFF104C97)),
                                  ),
                                  const Text(
                                    "Show this code to the driver",
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                  const SizedBox(height: 24),
                                  SizedBox(
                                    width: double.infinity,
                                    height: 50,
                                    child: OutlinedButton(
                                      onPressed: () => Navigator.pop(ctx),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.black,
                                        side: const BorderSide(color: Colors.grey),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      ),
                                      child: const Text("Close"),
                                    ),
                                  )
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          children: [
                            QrImageView(
                              data: qrData, // Use JSON string here
                              version: QrVersions.auto,
                              size: 180.0,
                              backgroundColor: Colors.white,
                            ),
                            const SizedBox(height: 8),
                            const Text("Tap to enlarge", style: TextStyle(fontSize: 12, color: Colors.blue, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 20),
                    
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
                        child: const Text("Close"),
                      ),
                    )
                  ],
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (ctx, anim1, anim2, child) {
        return Transform.scale(
          scale: CurvedAnimation(parent: anim1, curve: Curves.easeOutBack).value,
          child: FadeTransition(
            opacity: anim1,
            child: child,
          ),
        );
      },
    );
  }

  // --- Helper Widgets for Modern UI ---
  Widget _buildTimelineRow({required String time, required String location, required bool isStart}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 65,
          child: Text(
            isStart ? time : "", 
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF104C97)),
            textAlign: TextAlign.right,
          ),
        ),
        const SizedBox(width: 16),
        Column(
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: isStart ? const Color(0xFF104C97) : Colors.redAccent,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.3), blurRadius: 4)],
              ),
            ),
            if (isStart) 
              Container(
                width: 2, 
                height: 30, 
                color: Colors.grey.shade300,
              ),
          ],
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            location,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
        ),
      ],
    );
  }

  Widget _buildModernDetailItem(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Colors.grey.shade400),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.black87), overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ],
    );
  }

  // Helper for formatting Timestamp if needed
  String _formatDate(dynamic timestamp) {
    if (timestamp is Timestamp) {
      return DateFormat('hh:mm a').format(timestamp.toDate());
    }
    return "--:--";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 1. Primary Booking Stream
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('Bookings')
                .where('user_id', isEqualTo: user?.uid)
                .where('status', whereIn: ['confirmed', 'pending', 'arriving', 'on_board', 'onboard'])
                .orderBy('booking_time', descending: true)
                .limit(1)
                .snapshots(),
            builder: (context, snapshot) {
              
              LatLng? targetCenter = _uniKLLocation;
              Set<Marker> activeMarkers = _baseMarkers;
              
              if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
                final bookingData = snapshot.data!.docs.first.data() as Map<String, dynamic>;
                final String uniqueBookingId = snapshot.data!.docs.first.id;
                final String? scheduleId = bookingData['schedule_id']; 

                // --- 2. Secondary Stream: Real-Time Driver Location ---
                Stream<DocumentSnapshot>? scheduleStream;
                if (scheduleId != null && scheduleId.isNotEmpty) {
                  scheduleStream = FirebaseFirestore.instance.collection('Schedules').doc(scheduleId).snapshots();
                }

                return StreamBuilder<DocumentSnapshot>(
                  stream: scheduleStream,
                  builder: (context, scheduleSnap) {
                    
                    List<LatLng> pointsToRoute = [];
                    List<String> activeStopIds = [];
                    String? pickupId = bookingData['pickup_stop_id'];
                    String? dropoffId = bookingData['dropoff_stop_id'];
                    String? routeStartId;
                    String? routeEndId;

                    if (bookingData['route_id'] != null) {
                      String routeId = bookingData['route_id'];
                      if (_routePaths.containsKey(routeId)) {
                        activeStopIds = _routePaths[routeId]!;
                        for (var stopId in activeStopIds) {
                           if (_stopCoordinates.containsKey(stopId)) pointsToRoute.add(_stopCoordinates[stopId]!);
                        }
                      }
                      if (_routeMeta.containsKey(routeId)) {
                        routeStartId = _routeMeta[routeId]!['start'];
                        routeEndId = _routeMeta[routeId]!['end'];
                      }
                    } else {
                      if (pickupId != null) activeStopIds.add(pickupId);
                      if (dropoffId != null) activeStopIds.add(dropoffId);
                      if (pickupId != null && _stopCoordinates.containsKey(pickupId)) pointsToRoute.add(_stopCoordinates[pickupId]!);
                      if (dropoffId != null && _stopCoordinates.containsKey(dropoffId)) pointsToRoute.add(_stopCoordinates[dropoffId]!);
                    }

                    activeMarkers = _generateActiveMarkers(activeStopIds, pickupId: pickupId, dropoffId: dropoffId, routeStartId: routeStartId, routeEndId: routeEndId);

                    if (scheduleSnap.hasData && scheduleSnap.data!.exists) {
                      final scheduleData = scheduleSnap.data!.data() as Map<String, dynamic>;
                      final double? currentLat = scheduleData['current_lat']; 
                      final double? currentLng = scheduleData['current_lng'];

                      if (currentLat != null && currentLng != null) {
                        final driverPos = LatLng(currentLat, currentLng);
                        activeMarkers.add(Marker(
                          markerId: const MarkerId('driver_bus'),
                          position: driverPos,
                          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet), 
                          infoWindow: const InfoWindow(title: "Your Bus"),
                          zIndex: 10.0, 
                        ));
                      }
                    }

                    if (pointsToRoute.isNotEmpty) {
                      targetCenter = pointsToRoute.first;
                      if (_currentPolylineId != uniqueBookingId) {
                        Future.microtask(() => _fetchRoadPolyline(pointsToRoute, uniqueBookingId));
                      }
                    }

                    return MapWidget(
                      markers: activeMarkers, 
                      polylines: _polylines,
                      polygons: _polygons, // Pass the new polygons set here
                      initialCenter: _uniKLLocation,
                      targetLocation: targetCenter,
                    );
                  }
                );
              } 

              return MapWidget(
                markers: _baseMarkers, 
                polylines: const {},
                polygons: _polygons, // Pass the new polygons set here as well
                initialCenter: _uniKLLocation,
                targetLocation: _uniKLLocation,
              );
            },
          ),

          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildActiveRideCard(),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveRideCard() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('Bookings')
          .where('user_id', isEqualTo: user?.uid)
          .where('status', whereIn: ['confirmed', 'pending', 'arriving', 'on_board', 'onboard'])
          .orderBy('booking_time', descending: true)
          .limit(1)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const SizedBox.shrink();

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Container(
            margin: const EdgeInsets.all(20),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10)],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.directions_bus_outlined, size: 40, color: Colors.grey),
                SizedBox(height: 10),
                Text("No Active Ride", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Text("Book a shuttle to see live tracking.", style: TextStyle(color: Colors.grey)),
              ],
            ),
          );
        }

        final booking = snapshot.data!.docs.first;
        final data = booking.data() as Map<String, dynamic>;
        final status = data['status'] ?? 'unknown';
        final type = data['type'] ?? 'unknown';
        final bool isOnBoard = status == 'on_board' || status == 'onboard';
        
        Color statusColor = Colors.orange;
        String statusText = "Finding Driver...";
        
        if (status == 'confirmed') {
          statusColor = Colors.green;
          statusText = "Booking Confirmed";
        } else if (status == 'arriving') {
          statusColor = Colors.blue;
          statusText = "Shuttle Arriving";
        } else if (isOnBoard) {
          statusColor = const Color(0xFF104C97);
          statusText = "On Board";
        }

        String destinationText = "Campus";
        if (data['route_name'] != null) {
          destinationText = data['route_name'];
        } else if (data['dropoff_stop_id'] != null) {
          final stopId = data['dropoff_stop_id'];
          destinationText = _stopNames[stopId] ?? "Stop $stopId"; 
        } else if (data['destination'] != null) {
          destinationText = data['destination'];
        }

        return GestureDetector(
          onTap: () => _showBookingDetails(data, booking.id),
          child: Container(
            margin: const EdgeInsets.all(20),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10)],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 30,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        statusText,
                        style: TextStyle(color: statusColor, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const Spacer(),
                    Text(type == 'scheduled' ? "Scheduled" : "On-Demand", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 15),
                Row(
                  children: [
                    const Icon(Icons.location_on, color: Color(0xFF104C97)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Destination / Route", style: TextStyle(color: Colors.grey, fontSize: 10)),
                          Text(
                            destinationText,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (type == 'scheduled' && data['departure_time'] != null)
                   Padding(
                     padding: const EdgeInsets.only(top: 10.0),
                     child: Row(
                       children: [
                         const Icon(Icons.access_time, color: Colors.grey),
                         const SizedBox(width: 10),
                         Text("Departure: ${data['departure_time']}"),
                       ],
                     ),
                   ),
                const SizedBox(height: 20),
                
                // --- Dynamic Buttons based on Status ---
                if (isOnBoard) 
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _completeTrip(booking),
                      icon: const Icon(Icons.check_circle, size: 20),
                      label: const Text("Complete Trip", style: TextStyle(fontSize: 16)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _cancelBooking(booking),
                          style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red)),
                          child: const Text("Cancel Ride"),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => _showBookingDetails(data, booking.id),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF104C97),
                            foregroundColor: Colors.white,
                          ),
                          child: const Text("Boarding Pass"),
                        ),
                      ),
                    ],
                  )
              ],
            ),
          ),
        );
      },
    );
  }
}