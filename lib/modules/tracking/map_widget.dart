import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class MapWidget extends StatefulWidget {
  final Set<Marker> markers;
  final Set<Polyline> polylines;
  final Set<Polygon> polygons; // New: Polygon Support
  final LatLng initialCenter;
  final LatLng? targetLocation;

  const MapWidget({
    super.key,
    required this.markers,
    this.polylines = const {},
    this.polygons = const {}, // Initialize with empty set
    required this.initialCenter,
    this.targetLocation,
  });

  @override
  State<MapWidget> createState() => _MapWidgetState();
}

class _MapWidgetState extends State<MapWidget> {
  final Completer<GoogleMapController> _controller = Completer();

  Future<void> _moveCamera(LatLng target, {double zoom = 15.0}) async {
    final GoogleMapController controller = await _controller.future;
    controller.animateCamera(CameraUpdate.newLatLngZoom(target, zoom));
  }

  Future<void> _zoom(double amount) async {
    final GoogleMapController controller = await _controller.future;
    controller.animateCamera(CameraUpdate.zoomBy(amount));
  }

  void _showMapLegend() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Map Legend"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildLegendItem(Icons.location_on, Colors.green, "Start / Pickup Location"),
            const SizedBox(height: 12),
            _buildLegendItem(Icons.location_on, Colors.red, "End / Dropoff Location"),
            const SizedBox(height: 12),
            _buildLegendItem(Icons.location_on, Colors.blueAccent, "Intermediate Stop"),
            const SizedBox(height: 12),
            _buildLegendItem(Icons.timeline, const Color(0xFF104C97), "Route Path"),
             const SizedBox(height: 12),
            _buildLegendItem(Icons.crop_square, Colors.blue.withOpacity(0.5), "Zone Area"),
          ],
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

  Widget _buildLegendItem(IconData icon, Color color, String text) {
    return Row(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text, style: const TextStyle(fontSize: 14)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GoogleMap(
          mapType: MapType.normal,
          initialCameraPosition: CameraPosition(
            target: widget.initialCenter,
            zoom: 14.5,
          ),
          markers: widget.markers,
          polylines: widget.polylines,
          polygons: widget.polygons, // Pass polygons here
          myLocationEnabled: true,
          myLocationButtonEnabled: false, 
          zoomControlsEnabled: false,     
          onMapCreated: (GoogleMapController controller) {
            _controller.complete(controller);
          },
        ),

        Positioned(
          right: 16,
          bottom: 262,
          child: Column(
            children: [
              _buildMapButton(Icons.info_outline, _showMapLegend),
              const SizedBox(height: 8),

              _buildMapButton(Icons.add, () => _zoom(1.0)),
              const SizedBox(height: 8),
              
              _buildMapButton(Icons.remove, () => _zoom(-1.0)),
              const SizedBox(height: 8),
              
              _buildMapButton(Icons.gps_fixed, () {
                final target = widget.targetLocation ?? widget.initialCenter;
                _moveCamera(target);
              }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMapButton(IconData icon, VoidCallback onPressed) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IconButton(
        icon: Icon(icon, color: const Color(0xFF104C97)),
        onPressed: onPressed,
      ),
    );
  }
}