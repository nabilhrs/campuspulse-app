import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class LocationService {
  /// Check permissions and get current coordinates
  Future<Position?> getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    try {
      // Test if location services are enabled.
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return null; 
      }

      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return null;
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        return null;
      } 

      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (e) {
      debugPrint("Location error: $e");
      return null;
    }
  }

  /// Detect zone by finding the closest active stop within 3000m and returning its zone
  Future<Map<String, dynamic>?> detectZone([Position? currentPosition]) async {
    final position = currentPosition ?? await getCurrentLocation();
    if (position == null) return null;

    try {
      // OPTIMIZATION: Only fetch 'active' stops from the server to save database reads
      final stopsSnapshot = await FirebaseFirestore.instance
          .collection('Stops')
          .where('status', isEqualTo: 'active')
          .get();
          
      double? closestDistance;
      DocumentSnapshot? closestStopDoc;

      for (var doc in stopsSnapshot.docs) {
        final data = doc.data();
        
        final stopLat = data['lat'];
        final stopLng = data['lng'];

        if (stopLat == null || stopLng == null) continue;

        // Safely parse coordinates whether they are stored as doubles, ints, or strings
        double distance = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          (stopLat is num) ? stopLat.toDouble() : double.tryParse(stopLat.toString()) ?? 0.0,
          (stopLng is num) ? stopLng.toDouble() : double.tryParse(stopLng.toString()) ?? 0.0,
        );

        if (closestDistance == null || distance < closestDistance) {
          closestDistance = distance;
          closestStopDoc = doc;
        }
      }

      // If the closest stop is within 3000 meters (3km), look at its zone_ids array
      if (closestDistance != null && closestDistance <= 3000 && closestStopDoc != null) {
        final stopData = closestStopDoc.data() as Map<String, dynamic>;
        final zoneIds = stopData['zone_ids'];
        
        if (zoneIds is List && zoneIds.isNotEmpty) {
          String firstZoneId = zoneIds[0].toString();

          // Fetch the zone document from the Zones collection using that ID
          final zoneDoc = await FirebaseFirestore.instance
              .collection('Zones')
              .doc(firstZoneId)
              .get();

          if (zoneDoc.exists) {
            final zoneData = zoneDoc.data();
            return {
              'zone_id': zoneDoc.id,
              'name': zoneData?['name'] ?? 'Unknown Zone',
            };
          }
        }
      }
    } catch (e) {
      debugPrint("Detect zone error: $e");
    }
    
    return null;
  }
}