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
              colors: [Color(0xFF104C97), Color(0xFF0066CC)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF104C97).withOpacity(0.3),
                blurRadius: 15,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.map_outlined, color: Colors.white, size: 32),
              SizedBox(height: 12),
              Text(
                "Select Your Zone",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 4),
              Text(
                "Choose where you are starting your journey to see available shuttles.",
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          ),
        ),

        const SizedBox(height: 30),
        
        const Text(
          "Available Zones",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
        ),
        const SizedBox(height: 15),
        
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
                decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(12)),
                child: Text("Error loading zones: ${snapshot.error}", style: TextStyle(color: Colors.red.shade700)),
              );
            }
            
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: Padding(
                padding: EdgeInsets.all(20.0),
                child: CircularProgressIndicator(),
              ));
            }

            final docs = snapshot.data!.docs;
            
            // Empty State
            if (docs.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Column(
                    children: [
                      Icon(Icons.location_off_outlined, size: 60, color: Colors.grey.shade300),
                      const SizedBox(height: 10),
                      Text("No active zones found.", style: TextStyle(color: Colors.grey.shade500)),
                    ],
                  ),
                ),
              );
            }

            return ListView.separated(
              shrinkWrap: true, 
              physics: const NeverScrollableScrollPhysics(),
              itemCount: docs.length,
              separatorBuilder: (ctx, i) => const SizedBox(height: 12),
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
    return Material(
      color: Colors.white,
      elevation: 2,
      borderRadius: BorderRadius.circular(16),
      shadowColor: Colors.black.withOpacity(0.1),
      child: InkWell(
        onTap: () => onZoneSelected(zoneId, name),
        borderRadius: BorderRadius.circular(16),
        splashColor: const Color(0xFF104C97).withOpacity(0.1),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              // Icon Container
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.location_city_rounded, color: Color(0xFF104C97), size: 28),
              ),
              const SizedBox(width: 16),
              
              // Text Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      desc,
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              
              // Arrow
              const Icon(Icons.arrow_forward_ios_rounded, size: 18, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}