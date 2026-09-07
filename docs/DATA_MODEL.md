# Data model and core logic

Firestore collections and business rules **as used by the student mobile app**.

> **Scope.** CampusPulse spans three subsystems. The wider system writes fields this
> app never touches — `Bookings.ticket_status`, `check_in_time` and `check_out_time`;
> `Schedules.onboard_count` and `peak`; `Routes.service_type`; `Staffs.duty_status`
> and `current_trip_id`; and the whole `DRIVER_APPLICATIONS` collection. Those belong
> to the admin console and driver PWA. The project report holds the full cross-system
> data dictionary.

---

## Who writes booking status

The mobile app is largely a *reader* of booking state. It only ever writes:

- `searching` → `expired` (client-side 5-minute timeout, plus a refund transaction)
- `expired_acknowledged`, `cancelled` (user-initiated)
- `is_rated` (after the rating screen)

Every other transition — `confirmed`, `arriving`, `arrived`, `onboard`, `completed`,
`admin_review` — is written by the driver PWA or admin console and observed here
through `StreamBuilder`. If a status changes and no Dart code wrote it, that is
expected behaviour rather than a bug.

The QR boarding pass is the handoff point: the app renders
`{"bid": <bookingId>, "name": <studentName>}`, the driver's PWA scans it, and the
booking advances to `onboard`.

---

## Collections

### `Students` — doc id is the Firebase Auth `uid`

`student_id`, `full_name`, `username`, `student_email` (must be `@s.unikl.edu.my`),
`phone_number`, `photo_url`, `registration_date`, `status`
(`pending_verification` → `active`), `has_completed_profile`,
`balance` (Campus Credits, RM), `fcm_token`, `last_updated_token`,
`arrival_buffer` (minutes: 5 / 15 / 30),
`timetable` (map of day → list of time-slot strings)

### `Bookings`

`user_id`, `zone_id`, `zone_name`, `pickup_stop_id`, `pickup_stop_name`,
`dropoff_stop_id`, `dropoff_stop_name`, `pickup_lat`, `pickup_lng`, `booking_time`,
`request_time`, `fare`, `schedule_id`, `route_id`, `route_name`, `departure_time`,
`date` (`YYYY-MM-DD`), `shuttle_id`, `driver_id`, `driver_name`,
`candidate_driver_id`, `rejected_by[]`, `reminder_sent`, `is_rated`

- `type` — `scheduled` | `ondemand`
- `status` — `pending` | `searching` | `admin_review` | `confirmed` | `arriving` |
  `arrived` | `onboard` | `completed` | `expired` | `expired_acknowledged` | `cancelled`

### `Schedules`

`route_id`, `date`, `departure_time` (`HH:mm`), `etas` (map of stop_id → time),
`capacity` (13 where unset), `booked_count`, `shuttle_id`, `driver_id`, `status`

### `Stops`

`name`, `lat`, `lng`, `zone_ids[]`, `status`

### `Zones`

`zone_id`, `name`, `description`, `status`

### `Routes`

`route_id`, `route_name`, `zone_id`, `direction`, `stop_ids[]`, `start_stop_id`,
`end_stop_id`, `status`

### `Shuttles`

`is_online`, `job_status`, `current_lat`, `current_lng`

The app streams live vehicle position from here. The driver PWA also mirrors
coordinates onto `Schedules`, but no Dart code reads them from there.

### `Staffs`

`name` / `full_name`, `role` (`driver` | `admin`), `assigned_shuttle_id`, `profile_pic`

### `Transactions`

`user_id`, `type` (`credit` | `debit`), `amount`, `description`, `reference_id`,
`timestamp`

Append-only. The human-readable classification (top-up, ride payment, refund,
refund with penalty) is carried in `description`.

### `Ratings`

`booking_id`, `user_id`, `driver_id`, `rating`, `feedback_tags[]`, `comment`,
`timestamp`

### `Notifications`

`user_id`, `title`, `body`, `type`, `is_read`, `timestamp` — written only by Cloud
Functions.

### `Announcements`

`title`, `message`, `status`, `target_audience` — written only by the admin console.

---

## Core logic

### Fares and Campus Credits

The wallet currency is **Campus Credits**, a closed-loop balance denominated in RM.
Rides cost a flat **RM 2.00** (`_baseFare` 2.00 + `_serviceFee` 0.00), deducted in
`lib/modules/wallet/checkout_page.dart` inside a single Firestore transaction that
also writes the `Bookings` document and a `Transactions` debit, so a failure at any
step rolls the whole thing back. Scheduled bookings additionally increment
`Schedules.booked_count` in the same transaction, which is what keeps seat counts
correct under concurrent booking.

Top-ups credit the balance directly — there is no payment gateway.

### Cancellation

Early cancellation from My Bookings refunds the full fare. Cancelling within 15
minutes of departure, or once the driver is en route, applies a **50% penalty** and
refunds RM 1.00 (`lib/modules/tracking/tracking_page.dart`). Both paths write a
`Transactions` credit whose `description` records whether a penalty applied.

### Zone auto-detection

`lib/data/services/location_service.dart` finds the nearest `Stops` document with
`status == 'active'` within 3 km of the device and adopts its `zone_ids[0]`.
Coordinates are parsed defensively because Firestore stores them inconsistently as
numbers or strings. Permission denial returns null so the caller falls back to manual
selection.

### Smart Trip Planner

`lib/modules/recommendation/recommendation_page.dart` works backwards from each class:

```
ideal departure = class start − (travel time + arrival_buffer + traffic delay)
```

Travel time is 30 minutes normally, or 60 during the 07:00–09:00 and 17:00–19:00
peaks. Traffic delay comes from the Google Routes API in `TRAFFIC_AWARE` mode and is
only counted when the live duration exceeds `staticDuration` by more than five
minutes, so ordinary variance does not inflate every estimate.

It then selects the nearest real `Schedules` departure within a −45 to +180 minute
window that still has seats, and separately flags the closest full one as a near miss.

---

## Conventions

- **Null safety.** Firestore is schemaless and will return missing fields, so always
  provide fallbacks: `data['name'] ?? 'Unknown'`.
- **Concurrency.** Anything touching `balance` or `booked_count` must use
  `runTransaction`, and capacity must be checked *inside* the transaction.
- **Logging.** `debugPrint`, never `print` (enforced by the `avoid_print` lint).
- **Theming.** UniKL blue `#262562` and accent yellow `#F0AB00`, defined in
  `lib/main.dart`. Note the static pages in `assets/web/` and the web subsystems use
  `#104C97` for primary blue — the two halves do not currently match.
