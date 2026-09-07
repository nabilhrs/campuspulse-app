import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class RecentTransactionsPage extends StatefulWidget {
  const RecentTransactionsPage({super.key});

  @override
  State<RecentTransactionsPage> createState() => _RecentTransactionsPageState();
}

class _RecentTransactionsPageState extends State<RecentTransactionsPage> {
  final User? user = FirebaseAuth.instance.currentUser;

  void _showTransactionDetails(Map<String, dynamic> data, String id) {
    final isCredit = data['type'] == 'credit';
    final amount = (data['amount'] ?? 0.0).toDouble();
    final desc = data['description'] ?? (isCredit ? 'Top Up' : 'Trip Payment');
    final timestamp = (data['timestamp'] as Timestamp?)?.toDate();
    final dateStr = timestamp != null ? DateFormat('dd MMM yyyy, hh:mm a').format(timestamp) : 'Just now';
    final String refId = data['reference_id'] ?? 'N/A';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true, // Allows the sheet to take up more space if needed
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: isCredit ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1), shape: BoxShape.circle),
                  child: Icon(isCredit ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded, color: isCredit ? Colors.green : Colors.redAccent, size: 32),
                ),
                const SizedBox(height: 16),
                Text(desc, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900), textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(
                  "${isCredit ? '+' : '-'} RM ${amount.toStringAsFixed(2)}",
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 32, color: isCredit ? Colors.green : Colors.redAccent),
                ),
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 12),
                _buildDetailRow("Date", dateStr),
                _buildDetailRow("Transaction ID", id.toUpperCase().substring(0, 10)),
                if (refId != 'N/A') _buildDetailRow("Booking Ref", refId.toUpperCase().substring(0, 8)),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF262562), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                    child: const Text("Close", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8F9FA),
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF262562)),
        centerTitle: true,
        title: const Text("Transaction History", style: TextStyle(color: Color(0xFF262562), fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('Transactions').where('user_id', isEqualTo: user?.uid).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Color(0xFF262562)));
          if (snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.receipt_long, size: 60, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  Text("No transactions found.", style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.w600, fontSize: 16)),
                ],
              ),
            );
          }

          final docs = snapshot.data!.docs;
          docs.sort((a, b) {
            final tA = (a.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
            final tB = (b.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
            if (tA == null && tB == null) return 0;
            if (tA == null) return 1;
            if (tB == null) return -1;
            return tB.compareTo(tA);
          });

          return ListView.separated(
            padding: const EdgeInsets.all(24),
            physics: const BouncingScrollPhysics(),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;
              final isCredit = data['type'] == 'credit';
              final amount = (data['amount'] ?? 0.0).toDouble();
              final desc = data['description'] ?? (isCredit ? 'Top Up' : 'Trip Payment');
              final timestamp = (data['timestamp'] as Timestamp?)?.toDate();
              final dateStr = timestamp != null ? DateFormat('dd MMM, hh:mm a').format(timestamp) : 'Just now';

              return GestureDetector(
                onTap: () => _showTransactionDetails(data, doc.id),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 4))],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: isCredit ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1), shape: BoxShape.circle),
                        child: Icon(isCredit ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded, color: isCredit ? Colors.green : Colors.redAccent, size: 20),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(desc, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15), overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 4),
                            Text(dateStr, style: TextStyle(color: Colors.grey.shade500, fontSize: 12, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                      Text(
                        "${isCredit ? '+' : '-'} RM ${amount.toStringAsFixed(2)}",
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: isCredit ? Colors.green : Colors.redAccent),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}