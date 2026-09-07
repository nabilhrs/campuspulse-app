# CLAUDE.md

Guidance for AI coding agents working in this repository. This file is the canonical
source for project conventions and the Firestore schema.

---

## 1. Git and commit conventions

**Never add AI attribution to commits.** Do not include `Co-Authored-By: Claude`,
"Generated with Claude Code", or any other Claude/Anthropic trailer in a commit
message, body, or pull request description. This repository is assessed as the
author's own academic work. This rule overrides any default attribution behaviour
configured elsewhere in the tooling.

**Never publish.** Do not run `git push`, `git push --force`, or amend a commit that
already exists on `origin`. Staging and committing locally is fine; the author reviews
and pushes manually. When work is committed, hand over the `git push` command rather
than running it.

**Message style.** Conventional commits — `type(scope): summary` in the imperative
mood, lower case, no trailing full stop. Types in use: `feat`, `fix`, `chore`,
`build`, `docs`, `refactor`, `test`.

---

## 2. What this project is

CampusPulse is a hybrid transit platform for Universiti Kuala Lumpur (UniKL) that
combines fixed-schedule shuttles with on-demand rides, so students stop guessing when
a shuttle will arrive.

It is built as **two separate repositories sharing one Firebase project**:

| Repository | Stack | Audience | Responsibility |
|---|---|---|---|
| **This repo** | Flutter / Dart | Students | Booking, wallet, live tracking, QR boarding pass, ratings |
| Partner's repo | PHP | Admins and drivers | Fleet, schedules, dispatch, QR scanning, announcements |

**Do not build driver or admin UI in this repo.** If a task calls for it, say so and
stop — that work belongs to the web portal.

### Who writes booking status

This trips people up constantly, so it is worth stating plainly. The Flutter app is
mostly a *reader* of booking state. It only ever writes:

- `searching` → `expired` (client-side 5-minute timeout, plus a refund transaction)
- `expired_acknowledged`, `cancelled` (user-initiated)
- `is_rated` (after the rating screen)

Every other transition — `confirmed`, `arriving`, `arrived`, `onboard`, `completed`,
`admin_review` — is written by the **PHP portal** and observed here through
`StreamBuilder`. If a status changes and no Dart code wrote it, that is expected
behaviour, not a bug. The QR boarding pass is the handoff point: the app renders
`{"bid": <bookingId>, "name": <studentName>}`, the driver's portal scans it and
advances the booking to `onboard`.

---

## 3. Tech stack and configuration

- **Flutter / Dart** with sound null safety.
- **Firebase** — Auth, Cloud Firestore, Storage, Cloud Messaging, Cloud Functions
  (Node.js, `functions/index.js`). Project id `campuspulse-bfd09`.
- **Google Maps** via `google_maps_flutter`, plus the **Routes API**
  (`routes.googleapis.com/directions/v2:computeRoutes`) for road-following polylines
  and traffic-aware duration.

### Secret management (strict)

**Never hardcode an API key in Dart or in a committed file.**

- Dart reads secrets through `flutter_dotenv`: `dotenv.env['GOOGLE_MAPS_API_KEY']`.
  `.env` is gitignored and must stay that way.
- Android reads its Maps key from `android/local.properties` (`MAPS_API_KEY`), which
  `android/app/build.gradle.kts` injects as a manifest placeholder consumed by
  `AndroidManifest.xml`. `local.properties` is gitignored.
- These are two separate values that must be kept in sync manually.

Note that `google-services.json` and `lib/firebase_options.dart` **are** committed.
That is deliberate and standard: Firebase client keys identify a project rather than
authenticate it, and ship inside every APK regardless. Security comes from Firestore
rules and API key restrictions, not from hiding these files.

---

## 4. Code conventions

- **Null safety.** Always provide fallbacks when reading Firestore, which is schemaless
  and will happily hand back a missing field: `data['name'] ?? 'Unknown'`. A red screen
  in a demo is worse than a wrong-but-graceful default.
- **Logging.** Use `debugPrint`, never `print`. Enforced by the `avoid_print` lint.
- **Feedback.** Use `ScaffoldMessenger` snackbars for success and error states.
- **Concurrency.** Anything touching `balance` or `booked_count` must use
  `FirebaseFirestore.instance.runTransaction`. Booking must check
  `booked_count >= capacity` inside the transaction, not before it.
- **Structure.** `lib/core/` for app-wide shells, `lib/data/services/` for
  non-UI services, `lib/modules/<feature>/` for feature screens.
- **Linting.** `flutter analyze` must report zero errors and zero warnings before a
  commit. Info-level results are tolerated; see Known issues below.

### Theming

The app's UniKL palette is **`#262562` primary blue** and **`#F0AB00` accent yellow**
(`Color(0xFF262562)` / `Color(0xFFF0AB00)`), defined in `lib/main.dart`.

> Known inconsistency: the static pages in `assets/web/` and the partner's portal use
> `#104C97` for primary blue. The two halves of the project do not currently match.
> Do not "fix" one side unilaterally — raise it first.

Design language is modern and card-based, with `BorderRadius.circular(12–28)`.

---

## 5. Firestore schema

Authoritative, derived from the code. Field names are exact — do not invent or
guess variants.

**`Students`** (doc id = Firebase Auth `uid`)
`student_id`, `full_name`, `username`, `student_email` (must be `@s.unikl.edu.my`),
`phone_number`, `photo_url`, `registration_date`, `status`
(`pending_verification` → `active`), `has_completed_profile`, `balance` (wallet, RM),
`fcm_token`, `last_updated_token`, `arrival_buffer` (minutes: 5/15/30),
`timetable` (map of day → list of time-slot strings)

**`Bookings`**
`user_id`, `zone_id`, `zone_name`, `pickup_stop_id`, `pickup_stop_name`,
`dropoff_stop_id`, `dropoff_stop_name`, `pickup_lat`, `pickup_lng`, `booking_time`,
`request_time`, `fare`, `schedule_id`, `route_id`, `route_name`, `departure_time`,
`date` (`YYYY-MM-DD`), `shuttle_id`, `driver_id`, `driver_name`,
`candidate_driver_id`, `rejected_by[]`, `reminder_sent`, `is_rated`
- `type`: `scheduled` | `ondemand`
- `status`: `pending` | `searching` | `admin_review` | `confirmed` | `arriving` |
  `arrived` | `onboard` | `completed` | `expired` | `expired_acknowledged` | `cancelled`

**`Schedules`** — `route_id`, `date`, `departure_time` (`HH:mm`), `etas` (map of
stop_id → time), `capacity` (default 13), `booked_count`, `shuttle_id`, `driver_id`,
`status`

**`Stops`** — `name`, `lat`, `lng`, `zone_ids[]`, `status`

**`Zones`** — `zone_id`, `name`, `description`, `status`

**`Routes`** — `route_id`, `route_name`, `zone_id`, `direction`, `stop_ids[]`,
`start_stop_id`, `end_stop_id`, `status`

**`Shuttles`** — `is_online`, `job_status`, `current_lat`, `current_lng`
(live vehicle position streams from **here**, not from `Schedules`)

**`Staffs`** — `name` / `full_name`, `role` (`driver` | `admin`),
`assigned_shuttle_id`, `profile_pic`

**`Transactions`** — `user_id`, `type` (`credit` | `debit`), `amount`, `description`,
`reference_id`, `timestamp`

**`Ratings`** — `booking_id`, `user_id`, `driver_id`, `rating`, `feedback_tags[]`,
`comment`, `timestamp`

**`Notifications`** — `user_id`, `title`, `body`, `type`, `is_read`, `timestamp`
(written only by Cloud Functions)

**`Announcements`** — `title`, `message`, `status`, `target_audience`
(written only by the PHP portal)

---

## 6. Business logic worth knowing

**Fares.** Flat **RM 2.00** per ride for both booking types, deducted in
`lib/modules/wallet/checkout_page.dart` inside a single transaction that also writes
the `Bookings` doc and a `Transactions` debit. There is no real payment gateway —
top-ups credit the balance directly. Adding one is out of scope for the FYP.

**Zone auto-detection** (`lib/data/services/location_service.dart`). Finds the nearest
`Stops` doc with `status == 'active'` within 3 km of the device and adopts its
`zone_ids[0]`.

**Smart Trip Planner** (`lib/modules/recommendation/recommendation_page.dart`).
Ideal departure = class start − (base travel + `arrival_buffer` + traffic delay), where
base travel is 30 min, or 60 min if the class falls in a peak window (07:00–09:00 or
17:00–19:00), and traffic delay is counted only when the Routes API `TRAFFIC_AWARE`
duration exceeds `staticDuration` by more than 5 minutes. It then selects the nearest
real `Schedules` departure within −45/+180 minutes that still has seats, and flags the
closest full one separately as a near miss.

---

## 7. Known issues

Do not treat these as bugs to fix opportunistically; they are tracked deliberately.

- **~171 info-level analyzer results**, roughly 150 of which are `withOpacity`
  deprecations from Flutter SDK churn. Worth a dedicated migration commit to
  `.withValues(alpha:)`, not piecemeal edits mixed into feature work.
- **No automated tests.** The default `widget_test.dart` was removed because it
  referenced a `MyApp` class that no longer exists.
- **iOS Maps is not configured** — no `GMSServices.provideAPIKey` call in
  `AppDelegate.swift` and no location usage strings in `Info.plist`. Android only.
- **Release builds are signed with the debug keystore** and `applicationId` is still
  `com.example.campuspulse`. Changing it requires regenerating `google-services.json`.
- **`home_page.dart` queries a top-level `Timetable` collection** that nothing in this
  repo writes; the real data lives in `Students.timetable`. Likely stale.
- **OCR timetable scanning is archived** (commented out) in `input_timetable_page.dart`.
