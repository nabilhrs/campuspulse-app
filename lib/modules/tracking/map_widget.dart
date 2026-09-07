import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:campuspulse/data/services/location_service.dart';

class MapWidget extends StatefulWidget {
  final Set<Marker> markers;
  final Set<Polyline> polylines;
  final Set<Polygon> polygons;
  final LatLng initialCenter;
  final LatLng? targetLocation;

  const MapWidget({
    super.key,
    required this.markers,
    this.polylines = const {},
    this.polygons = const {},
    required this.initialCenter,
    this.targetLocation,
  });

  @override
  State<MapWidget> createState() => _MapWidgetState();
}

class _MapWidgetState extends State<MapWidget>
    with SingleTickerProviderStateMixin {
  final Completer<GoogleMapController> _controller = Completer();

  bool _hasCenteredOnTarget = false;

  // Expandable Menu & Zoom Logic
  late AnimationController _menuController;
  late Animation<double> _expandAnimation;
  bool _isMenuOpen = false;
  Timer? _zoomTimer;

  @override
  void initState() {
    super.initState();

    _menuController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );

    _expandAnimation = CurvedAnimation(
      parent: _menuController,
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _menuController.dispose();
    _zoomTimer?.cancel();
    super.dispose();
  }

  void _toggleMenu() {
    setState(() {
      _isMenuOpen = !_isMenuOpen;

      if (_isMenuOpen) {
        _menuController.forward();
      } else {
        _menuController.reverse();
      }
    });
  }

  void _startZoom(double amount) {
    _zoom(amount);

    _zoomTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => _zoom(amount),
    );
  }

  void _stopZoom() {
    _zoomTimer?.cancel();
  }

  @override
  void didUpdateWidget(MapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.targetLocation != null &&
        widget.targetLocation != oldWidget.targetLocation) {
      debugPrint(
          "[MAP_WIDGET] New target location received: ${widget.targetLocation}");

      if (!_hasCenteredOnTarget &&
          widget.targetLocation != widget.initialCenter) {
        _hasCenteredOnTarget = true;
        _moveCamera(widget.targetLocation!);
      }
    }
  }

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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        title: const Row(
          children: [
            Icon(Icons.map_rounded, color: Color(0xFF104C97)),
            SizedBox(width: 10),
            Text(
              "Map Legend",
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildLegendItem(
                Icons.directions_bus,
                const Color(0xFF104C97),
                "Live Shuttle (Online)",
              ),
              _buildLegendItem(
                Icons.directions_bus,
                Colors.orange,
                "Shuttle (Offline)",
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Divider(),
              ),
              _buildLegendItem(
                Icons.location_on,
                Colors.green,
                "Pickup / Start Location",
              ),
              _buildLegendItem(
                Icons.location_on,
                Colors.red,
                "Dropoff / End Location",
              ),
              _buildLegendItem(
                Icons.location_on,
                Colors.blueAccent,
                "Intermediate Stop",
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Divider(),
              ),
              _buildLegendItem(
                Icons.timeline,
                const Color(0xFF104C97),
                "Route Path",
              ),
              _buildLegendItem(
                Icons.crop_square,
                Colors.blue.withOpacity(0.5),
                "Service Zone Area",
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
                backgroundColor: const Color(0xFF104C97),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                "Got it!",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(IconData icon, Color color, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
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
          markers: Set<Marker>.of(widget.markers),
          polylines: Set<Polyline>.of(widget.polylines),
          polygons: Set<Polygon>.of(widget.polygons),
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          compassEnabled: false,
          mapToolbarEnabled: false,
          onMapCreated: (GoogleMapController controller) {
            _controller.complete(controller);
          },
        ),

        // --- COLLAPSIBLE MAP CONTROLS (Downward Expansion) ---
        Positioned(
          right: 10,
          top: 20,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Main Toggle Button at TOP
              GestureDetector(
                onTap: _toggleMenu,
                child: Container(
                  height: 56,
                  width: 56,
                  decoration: BoxDecoration(
                    color: const Color(0xFF262562),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    child: AnimatedIcon(
                      icon: AnimatedIcons.menu_close,
                      progress: _expandAnimation,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ),
              ),

              // Expand downward
              SizeTransition(
                sizeFactor: _expandAnimation,
                axisAlignment: -1.0,
                child: Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildMapActionButton(
                        Icons.help_outline_rounded,
                        _showMapLegend,
                      ),
                      const SizedBox(height: 12),

                      _buildHoldableActionButton(
                        Icons.add,
                        () => _startZoom(0.5),
                        _stopZoom,
                      ),
                      const SizedBox(height: 12),

                      _buildHoldableActionButton(
                        Icons.remove,
                        () => _startZoom(-0.5),
                        _stopZoom,
                      ),
                      const SizedBox(height: 12),

                      _buildMapActionButton(
                        Icons.gps_fixed,
                        () async {
                          final target = widget.targetLocation;

                          if (target != null &&
                              target != widget.initialCenter) {
                            _moveCamera(target);
                          } else {
                            final pos =
                                await LocationService().getCurrentLocation();

                            if (pos != null) {
                              _moveCamera(
                                LatLng(pos.latitude, pos.longitude),
                              );
                            } else {
                              _moveCamera(widget.initialCenter);
                            }
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMapActionButton(
    IconData icon,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        width: 48,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(
          icon,
          color: const Color(0xFF104C97),
          size: 22,
        ),
      ),
    );
  }

  Widget _buildHoldableActionButton(
    IconData icon,
    VoidCallback onPointerDown,
    VoidCallback onPointerUp,
  ) {
    return GestureDetector(
      onTapDown: (_) => onPointerDown(),
      onTapUp: (_) => onPointerUp(),
      onTapCancel: onPointerUp,
      child: Container(
        height: 48,
        width: 48,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(
          icon,
          color: const Color(0xFF104C97),
          size: 22,
        ),
      ),
    );
  }
}