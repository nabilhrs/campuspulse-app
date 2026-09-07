import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  Future<void> initNotification() async {
    debugPrint("!!! [FCM] Initializing Service...");

    await _fcm.requestPermission(
      alert: true,
      announcement: true,
      badge: true,
      sound: true,
    );

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'campus_pulse_alerts', 
      'Campus Pulse Notifications', 
      description: 'Used for important shuttle updates.',
      importance: Importance.max, 
      playSound: true,
      enableVibration: true,
      showBadge: true,
    );

    const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings = InitializationSettings(android: initializationSettingsAndroid);
    
    await _localNotifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        debugPrint("!!! [FCM] Notification Tapped in Foreground!");
      }
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint("!!! [FCM] Broadcast received in Foreground!");
      
      RemoteNotification? notification = message.notification;
      AndroidNotification? android = message.notification?.android;

      if (notification != null && android != null) {
        _localNotifications.show(
          notification.hashCode,
          notification.title,
          notification.body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              channel.id,
              channel.name,
              channelDescription: channel.description,
              importance: Importance.max,
              priority: Priority.high,
              icon: '@mipmap/ic_launcher',
            ),
          ),
        );
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint("!!! [FCM] Notification Tapped from Background!");
    });

    String? token = await _fcm.getToken();
    if (token != null) {
      // --- THE FIX: Subscribe to PHP Topics ---
      await _fcm.subscribeToTopic('all');
      await _fcm.subscribeToTopic('student');
      
      await saveTokenToDatabase();
    }
  }

  Future<void> saveTokenToDatabase() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      String? token = await _fcm.getToken();
      if (token != null) {
        await _db.collection('Students').doc(user.uid).set({
          'fcm_token': token,
          'last_updated_token': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint("!!! [FCM] Failed to sync token: $e");
    }
  }
}