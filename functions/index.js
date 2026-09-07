const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
admin.initializeApp();

// 1. Notify Full Shuttle (Fallback)
exports.notifyFullShuttle = functions.firestore
    .document("Schedules/{scheduleId}")
    .onUpdate(async (change, context) => {
        const after = change.after.data();
        const before = change.before.data();
        if (before.booked_count >= (before.capacity || 13)) return null;
        if (after.booked_count < (after.capacity || 13)) return null;

        const studentsSnap = await admin.firestore().collection("Students").where("fcm_token", "!=", null).get();
        const tokens = [];
        studentsSnap.forEach((doc) => tokens.push(doc.data().fcm_token));

        if (tokens.length > 0) {
            await admin.messaging().sendEachForMulticast({
                notification: { title: "Heads Up! 🚌", body: `The ${after.departure_time} shuttle is full.` },
                android: { notification: { channelId: "campus_pulse_alerts" } },
                tokens: tokens,
            });
        }
        return null;
    });

// 2. Notify Booking Status (Driver Arriving / Onboard / Completed / Timeout)
exports.notifyBookingStatus = functions.firestore
    .document("Bookings/{bookingId}")
    .onUpdate(async (change, context) => {
        const after = change.after.data();
        const before = change.before.data();

        // --- THE FIX: Force lowercasing and trimming to prevent PHP casing errors from skipping notifications ---
        const newStatus = (after.status || "").toLowerCase().trim();
        const oldStatus = (before.status || "").toLowerCase().trim();

        // If the status hasn't changed, ignore the update
        if (newStatus === oldStatus) return null;

        const studentDoc = await admin.firestore().collection("Students").doc(after.user_id).get();
        if (!studentDoc.exists || !studentDoc.data().fcm_token) return null;

        let title = ""; let body = ""; let type = "";

        if (newStatus === "arriving") {
            title = "🚌 Driver Arriving!";
            body = `Your shuttle is arriving at ${after.pickup_stop_name || 'your stop'}. Please get ready.`;
            type = "driver_arriving";
        } else if (newStatus === "arrived") {
            title = "📍 Driver Arrived!";
            body = `Your shuttle has arrived at ${after.pickup_stop_name || 'your stop'}. Please prepare your QR ticket to board.`;
            type = "arrived";
        } else if (newStatus === "onboard" || newStatus === "on_board") {
            title = "🚀 Trip Started!";
            body = `Welcome on board! You are now heading to ${after.dropoff_stop_name || after.route_name || 'your destination'}. Enjoy the ride!`;
            type = "trip_started";
        } else if (newStatus === "completed") {
            title = "🏁 You've Arrived!";
            body = `You have successfully reached your destination. Don't forget to rate your driver!`;
            type = "trip_completed";
        } else if (newStatus === "expired") {
            title = "⏳ Request Timeout";
            body = "No drivers accepted your request, or your shuttle was missed. Fare refunded.";
            type = "timeout";
        }

        // If it's a valid status change, log it and blast the push notification
        if (title !== "") {
            const batch = admin.firestore().batch();

            // Save to personal Notifications tab
            const notifRef = admin.firestore().collection("Notifications").doc();
            batch.set(notifRef, {
                user_id: after.user_id,
                title: title,
                body: body,
                type: type,
                is_read: false,
                timestamp: admin.firestore.FieldValue.serverTimestamp()
            });

            await batch.commit();

            // Blast True Push Notification
            await admin.messaging().send({
                notification: { title, body },
                android: { notification: { channelId: "campus_pulse_alerts" } },
                token: studentDoc.data().fcm_token
            }).catch(error => console.error("Error sending booking status push:", error));
        }
        return null;
    });

// 3. Log Announcement & Handle Scheduled Pushes (Fixed Clarity)
exports.processAnnouncement = functions.firestore
    .document("Announcements/{docId}")
    .onWrite(async (change, context) => {
        const data = change.after.exists ? change.after.data() : null;
        const beforeData = change.before.exists ? change.before.data() : null;

        if (!data || data.status !== "active") return null;

        // Only trigger ONCE when it becomes active (either created as active, or transitioned from scheduled)
        const isNewActive = !beforeData && data.status === "active";
        const isTransitionToActive = beforeData && beforeData.status !== "active" && data.status === "active";

        if (!isNewActive && !isTransitionToActive) return null;

        const studentsSnap = await admin.firestore().collection("Students").get();
        const batch = admin.firestore().batch();
        const tokens = [];

        studentsSnap.forEach(doc => {
            const studentData = doc.data();
            const aud = (data.target_audience || 'all').toLowerCase();

            // 1. Log into their personal Notification Center tab clearly
            if (aud === 'all' || aud === 'student') {
                const notifRef = admin.firestore().collection('Notifications').doc();
                batch.set(notifRef, {
                    user_id: doc.id,
                    title: data.title || "Campus Update",
                    body: data.message || "New announcement posted.",
                    type: "announcement",
                    is_read: false,
                    timestamp: admin.firestore.FieldValue.serverTimestamp()
                });
            }
            // 2. Gather tokens for the push
            if (studentData.fcm_token) tokens.push(studentData.fcm_token);
        });

        await batch.commit();

        // 3. Push to all gathered tokens using chunks to respect Firebase's 500 limit
        if (tokens.length > 0) {
            const chunkSize = 500;
            for (let i = 0; i < tokens.length; i += chunkSize) {
                const chunk = tokens.slice(i, i + chunkSize);
                await admin.messaging().sendEachForMulticast({
                    notification: {
                        // --- THE FIX: Bypassing generic titles to use exactly what the Admin typed ---
                        title: "📢 " + (data.title || "Campus Update"),
                        body: data.message || "Tap to view details."
                    },
                    android: { notification: { channelId: "campus_pulse_alerts" } },
                    tokens: chunk
                });
            }
        }
        return null;
    });

// 4. Upcoming Ride Reminder (Runs every 10 minutes)
exports.upcomingRideReminder = functions.pubsub.schedule('every 10 minutes').onRun(async (context) => {
    const now = new Date();
    // Convert server time to Malaysia Time (UTC+8)
    const myTime = new Date(now.getTime() + (8 * 60 * 60 * 1000));
    const todayStr = myTime.toISOString().split('T')[0]; // YYYY-MM-DD

    // Get all confirmed scheduled bookings for today
    const bookingsSnap = await admin.firestore().collection("Bookings")
        .where("type", "==", "scheduled")
        .where("date", "==", todayStr)
        .where("status", "==", "confirmed")
        .get();

    const batch = admin.firestore().batch();
    const promises = [];

    bookingsSnap.forEach(doc => {
        const data = doc.data();

        // Skip if we already reminded them
        if (data.reminder_sent === true) return;

        if (data.departure_time) {
            // Calculate difference in minutes
            const [bHour, bMin] = data.departure_time.split(':').map(Number);
            const bDate = new Date(myTime.getFullYear(), myTime.getMonth(), myTime.getDate(), bHour, bMin);

            const diffMins = (bDate.getTime() - myTime.getTime()) / (1000 * 60);

            // If departure is within the next 30 minutes
            if (diffMins > 0 && diffMins <= 30) {
                const notifRef = admin.firestore().collection("Notifications").doc();
                batch.set(notifRef, {
                    user_id: data.user_id,
                    title: "⏰ Upcoming Shuttle",
                    body: `Your shuttle leaves in ${Math.round(diffMins)} minutes. Time to head to ${data.pickup_stop_name || 'the stop'}!`,
                    type: "reminder",
                    is_read: false,
                    timestamp: admin.firestore.FieldValue.serverTimestamp()
                });

                // Update booking to prevent duplicate reminders
                batch.update(doc.ref, { reminder_sent: true });

                promises.push(
                    admin.firestore().collection("Students").doc(data.user_id).get().then(studentDoc => {
                        if (studentDoc.exists && studentDoc.data().fcm_token) {
                            return admin.messaging().send({
                                notification: {
                                    title: "⏰ Upcoming Shuttle",
                                    body: `Your shuttle leaves in ${Math.round(diffMins)} minutes. Time to head to ${data.pickup_stop_name || 'the stop'}!`
                                },
                                android: { notification: { channelId: "campus_pulse_alerts" } },
                                token: studentDoc.data().fcm_token
                            });
                        }
                    })
                );
            }
        }
    });

    if (promises.length > 0) {
        await batch.commit();
        await Promise.all(promises);
        console.log(`Sent ${promises.length} reminders.`);
    }
    return null;
});