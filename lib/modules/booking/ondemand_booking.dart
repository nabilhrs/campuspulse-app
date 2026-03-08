import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class OnDemandBooking extends StatefulWidget {
  final String zoneId;
  const OnDemandBooking({super.key, required this.zoneId});

  @override
  State<OnDemandBooking> createState() => _OnDemandBookingState();
}

class _OnDemandBookingState extends State<OnDemandBooking> {
  final User? user = FirebaseAuth.instance.currentUser;
  bool _isLoading = false;
  
  String? _selectedPickupStopId;
  String? _selectedDropoffStopId;

  Future<void> _requestRide() async {
    // 1. Basic Null Check
    if (_selectedPickupStopId == null || _selectedDropoffStopId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please select Pickup and Dropoff locations.")));
      return;
    }

    // 2. Same Location Check
    if (_selectedPickupStopId == _selectedDropoffStopId) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Pickup and Dropoff locations cannot be the same."),
        backgroundColor: Colors.red,
      ));
      return;
    }

    setState(() => _isLoading = true);
    
    try {
      await FirebaseFirestore.instance.collection('Bookings').add({
        'user_id': user!.uid,
        'type': 'ondemand',
        'status': 'pending', 
        'zone_id': widget.zoneId,
        'pickup_stop_id': _selectedPickupStopId,
        'dropoff_stop_id': _selectedDropoffStopId,
        'request_time': FieldValue.serverTimestamp(),
      });

      if(mounted) {
        showDialog(
          context: context, 
          builder: (_) => AlertDialog(
            title: const Text("Request Sent"),
            content: const Text("We are looking for a driver nearby."),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("OK"))],
          )
        );
      }
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Request failed: $e")));
    } finally {
      if(mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const Icon(Icons.hail, size: 60, color: Color(0xFFF0AB00)),
          const SizedBox(height: 10),
          const Text(
            "On-Demand Request",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF104C97)),
          ),
          const SizedBox(height: 5),
          const Text(
            "Available Everyday",
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 30),

          // Fetch Stops for Dropdowns
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('Stops')
                  .where('zone_ids', arrayContains: widget.zoneId)
                  .where('status', isEqualTo: 'active')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) return Text("Error loading stops: ${snapshot.error}");
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                final stops = snapshot.data!.docs;
                
                if (stops.isEmpty) return const Center(child: Text("No stops found for this zone."));

                // Convert docs to DropdownItems
                final dropdownItems = stops.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return DropdownMenuItem(
                    value: data['stop_id'] as String,
                    child: Text(
                      data['name'] ?? 'Unknown Stop',
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList();

                return ListView(
                  children: [
                    // Pickup Dropdown
                    DropdownButtonFormField<String>(
                      value: _selectedPickupStopId,
                      decoration: const InputDecoration(
                        labelText: "Pickup Location",
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.my_location),
                      ),
                      items: dropdownItems,
                      onChanged: (val) {
                        setState(() {
                          _selectedPickupStopId = val;
                          // Optional: Clear dropoff if it matches the new pickup
                          if (_selectedDropoffStopId == val) _selectedDropoffStopId = null;
                        });
                      },
                    ),
                    
                    const SizedBox(height: 20),

                    // Dropoff Dropdown
                    DropdownButtonFormField<String>(
                      value: _selectedDropoffStopId,
                      decoration: const InputDecoration(
                        labelText: "Dropoff Location",
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.location_on),
                      ),
                      items: dropdownItems,
                      onChanged: (val) => setState(() => _selectedDropoffStopId = val),
                      // Visual validation: Red border if same as pickup
                      validator: (val) => val != null && val == _selectedPickupStopId 
                          ? "Cannot be same as Pickup" 
                          : null,
                    ),
                  ],
                );
              },
            ),
          ),
          
          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _requestRide,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF104C97),
                foregroundColor: Colors.white,
              ),
              child: _isLoading 
                ? const CircularProgressIndicator(color: Colors.white)
                : const Text("Request Shuttle", style: TextStyle(fontSize: 18)),
            ),
          ),
        ],
      ),
    );
  }
}