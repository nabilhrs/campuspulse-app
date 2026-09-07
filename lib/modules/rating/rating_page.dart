import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

class RatingPage extends StatefulWidget {
  final String bookingId;
  final String driverId;

  const RatingPage({super.key, required this.bookingId, required this.driverId});

  @override
  State<RatingPage> createState() => _RatingPageState();
}

class _RatingPageState extends State<RatingPage> {
  final User? user = FirebaseAuth.instance.currentUser;
  
  double _rating = 0.0;
  final Set<String> _selectedTags = {};
  final TextEditingController _commentController = TextEditingController();
  bool _isSubmitting = false;

  late Future<Map<String, dynamic>> _driverDataFuture;

  @override
  void initState() {
    super.initState();
    _driverDataFuture = _fetchDriverData();
  }

  // --- FEATURE 3: Fetch Driver Data & Resolve Profile Pic URL ---
  Future<Map<String, dynamic>> _fetchDriverData() async {
    String name = "Your Driver";
    String? photoUrl;

    try {
      final doc = await FirebaseFirestore.instance.collection('Staffs').doc(widget.driverId).get();
      
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        name = data['full_name'] ?? name;
        
        final path = data['profile_pic'];
        if (path != null && path.toString().trim().isNotEmpty) {
          if (path.toString().startsWith('http')) {
            photoUrl = path;
          } else {
            // Resolve Storage Path to Download URL
            try {
              photoUrl = await FirebaseStorage.instance.ref(path).getDownloadURL();
            } catch (e) {
              debugPrint("Error resolving driver profile pic: $e");
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Error fetching driver doc: $e");
    }

    return {
      'name': name,
      'photoUrl': photoUrl,
    };
  }

  // --- FEATURE 1: Dynamic Presets based on Rating ---
  List<String> get _currentPresets {
    if (_rating >= 5.0) {
      return ["Professional", "Safe Driving", "Friendly", "On Time", "Clean Shuttle", "Great Music"];
    } else if (_rating == 4.0) {
      return ["Safe Driving", "Clean", "Friendly", "On Time", "Comfortable"];
    } else if (_rating == 3.0) {
      return ["Average", "A bit late", "Not very clean", "Quiet", "Rushed"];
    } else if (_rating == 2.0) {
      return ["Unsafe Driving", "Late", "Rude", "Dirty", "Uncomfortable"];
    }
    // FEATURE 2: Return empty for 1 star (handled by hiding the wrap)
    return []; 
  }

  // --- FEATURE 2: Dynamic Hints ---
  String get _commentHint {
    if (_rating <= 2.0) {
      return "Please tell us what went wrong so we can improve...";
    } else if (_rating == 3.0) {
      return "How can we improve?";
    }
    return "Leave a note for the driver... (Optional)";
  }

  String get _commentTitle {
    if (_rating <= 2.0) {
      return "Please tell us what went wrong";
    }
    return "Additional Comments (Optional)";
  }

  String get _presetTitle {
    if (_rating >= 4.0) return "What went well?";
    if (_rating > 1.0) return "What could be improved?";
    return ""; // Hidden for 1 star
  }

  Future<void> _submitFeedback() async {
    if (_rating == 0.0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Please select a star rating first!"),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          margin: const EdgeInsets.all(20),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final bookingRef = FirebaseFirestore.instance.collection('Bookings').doc(widget.bookingId);
        final ratingRef = FirebaseFirestore.instance.collection('Ratings').doc();

        // 1. Create the rating record
        tx.set(ratingRef, {
          'booking_id': widget.bookingId,
          'user_id': user?.uid,
          'driver_id': widget.driverId,
          'rating': _rating,
          'feedback_tags': _selectedTags.toList(),
          'comment': _commentController.text.trim(),
          'timestamp': FieldValue.serverTimestamp(),
        });

        // 2. Mark the booking as rated
        tx.update(bookingRef, {'is_rated': true});
      });

      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Thank you for your feedback!"),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          margin: const EdgeInsets.all(20),
        ),
      );
      
      Navigator.pop(context, 'rated');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error submitting feedback: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
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
        title: const Text("Rate Your Driver", style: TextStyle(color: Color(0xFF262562), fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _driverDataFuture,
        builder: (context, snapshot) {
          String driverName = "Your Driver";
          String? photoUrl;
          
          if (snapshot.hasData) {
            driverName = snapshot.data!['name'];
            photoUrl = snapshot.data!['photoUrl'];
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Driver Avatar
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 8))],
                  ),
                  child: CircleAvatar(
                    radius: 45,
                    backgroundColor: const Color(0xFF262562).withOpacity(0.1),
                    backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
                    child: photoUrl == null ? const Icon(Icons.person, size: 40, color: Color(0xFF262562)) : null,
                  ),
                ),
                const SizedBox(height: 16),
                Text("How was your trip with", style: TextStyle(color: Colors.grey.shade600, fontSize: 16)),
                const SizedBox(height: 4),
                Text(driverName, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF262562))),
                
                const SizedBox(height: 40),

                // Star Rating
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (index) {
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _rating = index + 1.0;
                          // Clear previous tags when star rating category changes to prevent mismatched feedback
                          _selectedTags.clear(); 
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(
                          index < _rating ? Icons.star_rounded : Icons.star_outline_rounded,
                          color: index < _rating ? const Color(0xFFF0AB00) : Colors.grey.shade300,
                          size: 50,
                        ),
                      ),
                    );
                  }),
                ),

                const SizedBox(height: 40),

                // Animated Form (Appears after rating is selected)
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 400),
                  opacity: _rating > 0 ? 1.0 : 0.0,
                  child: IgnorePointer(
                    ignoring: _rating == 0.0,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Dynamic Presets (Hidden for 1-Star)
                        if (_rating > 1.0) ...[
                          Text(_presetTitle, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 12),
                          
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: _currentPresets.map((tag) {
                              final isSelected = _selectedTags.contains(tag);
                              return FilterChip(
                                label: Text(
                                  tag, 
                                  style: TextStyle(
                                    color: isSelected ? const Color(0xFFE69B00) : Colors.grey.shade700, 
                                    fontWeight: FontWeight.bold
                                  )
                                ),
                                selected: isSelected,
                                backgroundColor: Colors.white,
                                selectedColor: const Color(0xFFFFF9C4), 
                                checkmarkColor: const Color(0xFFE69B00),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20), 
                                  side: BorderSide(color: isSelected ? const Color(0xFFF0AB00).withOpacity(0.5) : Colors.grey.shade200)
                                ),
                                onSelected: (val) {
                                  setState(() {
                                    if (val) _selectedTags.add(tag);
                                    else _selectedTags.remove(tag);
                                  });
                                },
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 24),
                        ],
                        
                        // Dynamic Comment Box
                        Text(_commentTitle, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 12),
                        
                        TextField(
                          controller: _commentController,
                          maxLines: 3,
                          decoration: InputDecoration(
                            hintText: _commentHint,
                            hintStyle: TextStyle(color: Colors.grey.shade400),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: BorderSide(color: Colors.grey.shade200),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: BorderSide(color: Colors.grey.shade200),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: const BorderSide(color: Color(0xFF262562), width: 2),
                            ),
                          ),
                        ),
                        
                        const SizedBox(height: 40),
                        
                        // Submit Button
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            onPressed: _isSubmitting ? null : _submitFeedback,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF262562),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              elevation: 5,
                              shadowColor: const Color(0xFF262562).withOpacity(0.4),
                            ),
                            child: _isSubmitting 
                                ? const CircularProgressIndicator(color: Colors.white)
                                : const Text("Submit Feedback", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                          ),
                        ),
                        const SizedBox(height: 16),
                        
                        // Skip Button
                        Center(
                          child: TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text("Skip", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 16)),
                          ),
                        )
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }
      ),
    );
  }
}