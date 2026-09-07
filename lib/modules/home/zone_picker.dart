import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ZonePicker extends StatelessWidget {
  final Function(String zoneId, String zoneName) onZoneSelected;

  const ZonePicker({super.key, required this.onZoneSelected});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // --- 1. Visual Header (Hero Section) ---
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF262562), Color(0xFF0066CC)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(28), // Updated to 28 for modern feel
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF262562).withOpacity(0.3),
                blurRadius: 25, // Softer shadow
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                right: -20,
                bottom: -20,
                child: Icon(Icons.map, size: 120, color: Colors.white.withOpacity(0.1)),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
                    child: const Icon(Icons.near_me, color: Colors.white, size: 24),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "Select Your Zone",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Choose where you are starting your journey to see available shuttles.",
                    style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 36),
        
        const Text(
          "Available Zones",
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.black, letterSpacing: -0.5),
        ),
        const SizedBox(height: 16),
        
        // --- 2. Dynamic Zone List ---
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('Zones')
              .where('status', isEqualTo: 'active')
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(20)),
                child: Text("Error loading zones: ${snapshot.error}", style: TextStyle(color: Colors.red.shade700)),
              );
            }
            
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: Padding(
                padding: EdgeInsets.all(40.0),
                child: CircularProgressIndicator(color: Color(0xFF262562)),
              ));
            }

            // FILTER LOGIC: Exclude Main Campus
            final docs = snapshot.data!.docs.where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final String name = (data['name'] ?? '').toString().toLowerCase();
              return !name.contains('main campus'); 
            }).toList();
            
            // Empty State
            if (docs.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Column(
                    children: [
                      Icon(Icons.location_off_rounded, size: 60, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text("No active zones found.", style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              );
            }

            return ListView.separated(
              shrinkWrap: true, 
              physics: const NeverScrollableScrollPhysics(),
              itemCount: docs.length,
              separatorBuilder: (ctx, i) => const SizedBox(height: 16),
              itemBuilder: (context, index) {
                final data = docs[index].data() as Map<String, dynamic>;
                final String name = data['name'] ?? 'Unknown Zone';
                final String desc = data['description'] ?? 'UniKL Shuttle Service Area';
                final String zoneId = data['zone_id'] ?? docs[index].id;

                return _buildZoneCard(context, name, desc, zoneId);
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildZoneCard(BuildContext context, String name, String desc, String zoneId) {
    return GestureDetector(
      onTap: () => onZoneSelected(zoneId, name),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            // Icon Container
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.location_city_rounded, color: Color(0xFF262562), size: 24),
            ),
            const SizedBox(width: 16),
            
            // Text Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.black87),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    desc,
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 13, fontWeight: FontWeight.w500),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            
            // Arrow
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.grey.shade50, shape: BoxShape.circle),
              child: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}