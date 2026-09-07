import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:campuspulse/modules/wallet/recent_transactions_page.dart';

class TopUpPage extends StatefulWidget {
  const TopUpPage({super.key});

  @override
  State<TopUpPage> createState() => _TopUpPageState();
}

class _TopUpPageState extends State<TopUpPage> {
  final User? user = FirebaseAuth.instance.currentUser;
  double? _selectedAmount;
  bool _isProcessing = false;

  final TextEditingController _customAmountController = TextEditingController();
  final FocusNode _customFocus = FocusNode();
  String? _customError;

  final List<double> _presetAmounts = [5.0, 10.0, 20.0, 50.0];

  @override
  void dispose() {
    _customAmountController.dispose();
    _customFocus.dispose();
    super.dispose();
  }

  void _showFloatingSnackBar(String message, {Color color = Colors.red}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.only(bottom: 15, left: 20, right: 20),
        elevation: 8,
      ),
    );
  }

  Future<void> _processTopUp() async {
    if (_selectedAmount == null || user == null) return;
    setState(() => _isProcessing = true);

    final double amountToTopUp = _selectedAmount!;

    try {
      final studentRef = FirebaseFirestore.instance.collection('Students').doc(user!.uid);

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final snapshot = await transaction.get(studentRef);
        if (!snapshot.exists) throw Exception("Student record not found.");

        final currentBalance = (snapshot.data()?['balance'] ?? 0.0).toDouble();
        final newBalance = currentBalance + amountToTopUp;

        transaction.update(studentRef, {'balance': newBalance});

        final txnRef = FirebaseFirestore.instance.collection('Transactions').doc();
        transaction.set(txnRef, {
          'user_id': user!.uid,
          'type': 'credit',
          'amount': amountToTopUp,
          'description': 'Top Up - RM ${amountToTopUp.toStringAsFixed(0)}',
          'timestamp': FieldValue.serverTimestamp(),
        });
      });

      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 20),
              Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.green.shade50, shape: BoxShape.circle), child: const Icon(Icons.check_circle, color: Colors.green, size: 60)),
              const SizedBox(height: 20),
              const Text("Top Up Successful!", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900), textAlign: TextAlign.center),
              const SizedBox(height: 10),
              Text("RM ${amountToTopUp.toStringAsFixed(2)} has been credited to your wallet.", style: const TextStyle(color: Colors.grey), textAlign: TextAlign.center),
              const SizedBox(height: 24),
              SizedBox(width: double.infinity, height: 50, child: ElevatedButton(onPressed: () => Navigator.pop(context), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF262562), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))), child: const Text("Done", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))))
            ],
          ),
        ),
      );

      setState(() {
        _selectedAmount = null;
        _customAmountController.clear();
        _customError = null;
      });
    } catch (e) {
      _showFloatingSnackBar("Top up failed: $e");
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

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
      isScrollControlled: true, 
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
        title: const Text("Campus Credits", style: TextStyle(color: Color(0xFF262562), fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- BALANCE CARD ---
            StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('Students').doc(user?.uid).snapshots(),
              builder: (context, snapshot) {
                final balance = (snapshot.data?.data() as Map<String, dynamic>?)?['balance']?.toDouble() ?? 0.0;

                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF262562), Color(0xFF1A6FD4)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [BoxShadow(color: const Color(0xFF262562).withOpacity(0.35), blurRadius: 20, offset: const Offset(0, 10))],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), shape: BoxShape.circle), child: const Icon(Icons.account_balance_wallet, color: Colors.white, size: 24)),
                          const SizedBox(width: 12),
                          const Text("Available Balance", style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text("RM ${balance.toStringAsFixed(2)}", style: const TextStyle(color: Colors.white, fontSize: 42, fontWeight: FontWeight.w900, letterSpacing: -1)),
                      const SizedBox(height: 8),
                      Text("Student Wallet · ${user?.email?.split('@').first ?? 'User'}", style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13, fontWeight: FontWeight.w500)),
                    ],
                  ),
                );
              },
            ),

            const SizedBox(height: 32),

            // --- TOP UP SECTION ---
            const Text("Quick Top Up", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
            const SizedBox(height: 6),
            Text("Select an amount to add to your wallet.", style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
            const SizedBox(height: 20),

            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: _presetAmounts.map((amount) {
                final isSelected = _selectedAmount == amount;
                return GestureDetector(
                  onTap: () {
                    _customFocus.unfocus();
                    _customAmountController.clear();
                    setState(() {
                      _selectedAmount = amount;
                      _customError = null;
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: (MediaQuery.of(context).size.width - 60) / 2,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFF262562) : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: isSelected ? const Color(0xFF262562) : Colors.grey.shade200, width: 2),
                      boxShadow: isSelected ? [BoxShadow(color: const Color(0xFF262562).withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 8))] : [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
                    ),
                    child: Column(
                      children: [
                        Text("RM ${amount.toStringAsFixed(0)}", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: isSelected ? Colors.white : const Color(0xFF262562))),
                        const SizedBox(height: 4),
                        Text(amount >= 20 ? "Best Value" : "Standard", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isSelected ? Colors.white70 : Colors.grey.shade500)),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 24),

            // --- THE FIX: Custom Amount Locked to Whole Numbers ---
            const Text("Custom Amount", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
            const SizedBox(height: 12),
            TextField(
              controller: _customAmountController,
              focusNode: _customFocus,
              keyboardType: TextInputType.number, 
              onTap: () {
                if (_customAmountController.text.isEmpty) {
                  _customAmountController.text = "5";
                  _customAmountController.selection = TextSelection.fromPosition(TextPosition(offset: _customAmountController.text.length));
                  setState(() {
                    _selectedAmount = 5.0;
                    _customError = null;
                  });
                }
              },
              onChanged: (val) {
                if (val.isEmpty) {
                  setState(() {
                    _customError = "Minimum amount is RM 5";
                    _selectedAmount = null;
                  });
                  return;
                }
                
                final valInt = int.tryParse(val);
                if (valInt == null) {
                  setState(() {
                    _customError = "Enter whole numbers only";
                    _selectedAmount = null;
                  });
                  return;
                }
                
                if (valInt < 5) {
                  setState(() {
                    _customError = "Minimum amount is RM 5";
                    _selectedAmount = null;
                  });
                } else if (valInt > 50) {
                  setState(() {
                    _customError = "Maximum amount is RM 50";
                    _selectedAmount = null;
                  });
                } else {
                  setState(() {
                    _customError = null;
                    _selectedAmount = valInt.toDouble();
                  });
                }
              },
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF262562)),
              decoration: InputDecoration(
                prefixText: "RM ",
                prefixStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF262562)),
                hintText: "0",
                hintStyle: TextStyle(color: Colors.grey.shade400),
                errorText: _customError,
                errorStyle: const TextStyle(fontWeight: FontWeight.bold),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: Colors.grey.shade200, width: 2)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: Colors.grey.shade200, width: 2)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: Color(0xFF262562), width: 2)),
                errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: Colors.redAccent, width: 2)),
                focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: Colors.redAccent, width: 2)),
              ),
            ),

            const SizedBox(height: 28),

            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton(
                onPressed: (_selectedAmount == null || _isProcessing) ? null : _processTopUp,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF0AB00),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade300,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  elevation: _selectedAmount != null ? 8 : 0,
                  shadowColor: const Color(0xFFF0AB00).withOpacity(0.5),
                ),
                child: _isProcessing
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                    : Text(_selectedAmount != null ? "Confirm Top Up · RM ${_selectedAmount!.toStringAsFixed(0)}" : "Select an Amount", style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, letterSpacing: 0.3)),
              ),
            ),

            const SizedBox(height: 40),

            // --- TRANSACTION HISTORY HEADER ---
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Recent Transactions", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                TextButton(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RecentTransactionsPage())),
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  child: const Row(
                    children: [
                      Text("See All", style: TextStyle(color: Color(0xFF262562), fontWeight: FontWeight.bold)),
                      Icon(Icons.chevron_right, size: 18, color: Color(0xFF262562))
                    ],
                  ),
                )
              ],
            ),
            const SizedBox(height: 16),

            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('Transactions').where('user_id', isEqualTo: user?.uid).snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Color(0xFF262562)));
                if (snapshot.data!.docs.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(Icons.receipt_long, size: 48, color: Colors.grey.shade300),
                          const SizedBox(height: 12),
                          Text("No transactions yet.", style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
                        ],
                      ),
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
                
                final recentDocs = docs.take(3).toList();

                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: recentDocs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final doc = recentDocs[index];
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
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}