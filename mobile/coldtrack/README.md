# ColdTrack Mobile

Flutter app for dispatch riders transporting temperature-sensitive vaccines.
Streams live sensor telemetry from the existing AWS IoT Core backend via
API Gateway + Lambda + DynamoDB, predicts spoilage risk, and guides riders
to the nearest viable cold storage centre.

---

## Quick start

```bash
cd mobile/coldtrack
cp .env.example .env        # then fill in real values
flutter pub get
flutter run
```

On first launch the app requests **location** and **notifications**
permissions. Without them the trip screen still works, but the map and
alert toasts will be degraded.

---

## AWS setup checklist

The mobile app expects three AWS resources to already be deployed. Work
through this list with the backend team before you ship.

### 1. Cognito Identity Pool (unauthenticated guest access)

1. AWS Console → **Cognito** → **Identity pools** → **Create identity pool**
2. Name: `coldtrack-mobile-guest`
3. Authentication providers: leave blank (guest-only)
4. **Enable access to unauthenticated identities**
5. Create — copy the **Identity pool ID** into `.env` as
   `COGNITO_IDENTITY_POOL_ID`
6. Cognito will auto-create two IAM roles. Edit the
   `Cognito_coldtrack-mobile-guestUnauth_Role` and attach:

   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": ["execute-api:Invoke"],
         "Resource": "arn:aws:execute-api:eu-west-1:*:*/prod/GET/devices/*"
       },
       {
         "Effect": "Allow",
         "Action": ["execute-api:Invoke"],
         "Resource": "arn:aws:execute-api:eu-west-1:*:*/prod/POST/incidents"
       },
       {
         "Effect": "Allow",
         "Action": ["execute-api:Invoke"],
         "Resource": "arn:aws:execute-api:eu-west-1:*:*/prod/GET/storage-centres"
       }
     ]
   }
   ```

### 2. API Gateway endpoints

Confirm these routes exist on the stage named in `API_GATEWAY_BASE_URL`:

| Method | Path                                   | Lambda                      |
| ------ | -------------------------------------- | --------------------------- |
| GET    | `/devices/{deviceId}/readings`         | readings-list               |
| GET    | `/devices/{deviceId}/readings/latest`  | readings-latest             |
| POST   | `/incidents`                           | incidents-writer            |
| GET    | `/storage-centres`                     | storage-centres (optional)  |

`/storage-centres` is optional — if it is not deployed, the app falls back
to the hardcoded centres in `lib/utils/constants.dart`.

### 3. Google Maps API key

1. Google Cloud Console → **APIs & Services** → **Credentials** →
   Create API key.
2. Enable **Maps SDK for Android** and **Maps SDK for iOS**.
3. Paste into `.env` as `GOOGLE_MAPS_API_KEY`.
4. **Android**: add inside `<application>` in
   `android/app/src/main/AndroidManifest.xml`:
   ```xml
   <meta-data
       android:name="com.google.android.geo.API_KEY"
       android:value="YOUR_KEY"/>
   ```
5. **iOS**: in `ios/Runner/AppDelegate.swift`:
   ```swift
   import GoogleMaps
   GMSServices.provideAPIKey("YOUR_KEY")
   ```

### 4. Android permissions

`android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
```

### 5. iOS permissions

`ios/Runner/Info.plist`:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>ColdTrack needs your location to route you to the nearest cold store.</string>
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>ColdTrack monitors shipments in the background.</string>
```

---

## DynamoDB expected table schema

The readings-list Lambda queries a DynamoDB table with this shape:

| Attribute     | Type   | Notes                                       |
| ------------- | ------ | ------------------------------------------- |
| `deviceId`    | String | **Partition key** — matches `IOT_DEVICE_ID` |
| `timestamp`   | String | **Sort key** — ISO-8601 UTC                 |
| `temperature` | Number | Celsius                                     |
| `humidity`    | Number | Optional                                    |
| `battery`     | Number | Optional                                    |

A `limit=20` query returns the most recent 20 readings ordered by
`timestamp` descending. The mobile app reverses them locally for the
time-series chart.

### Expected response

`GET /devices/{deviceId}/readings?limit=20`:

```json
{
  "deviceId": "coldtrack-device-001",
  "readings": [
    { "timestamp": "2026-04-21T14:30:05Z", "temperature": 4.2, "humidity": 60.1 },
    { "timestamp": "2026-04-21T14:30:00Z", "temperature": 4.1, "humidity": 60.0 }
  ],
  "latestReading": {
    "timestamp": "2026-04-21T14:30:05Z",
    "temperature": 4.2
  }
}
```

`SensorReading.fromJson` is tolerant — it also accepts a flat top-level
object (matching the ESP32 firmware's MQTT payload) and a nested
`{ "sensors": { "temperature": ..., "humidity": ... } }` shape.

---

## Switching from REST polling to MQTT (Phase 2)

Phase 1 polls `GET /devices/{deviceId}/readings/latest` every 5 seconds.
Phase 2 replaces the poll with a live MQTT stream over WebSockets.

### Enable Phase 2

1. In `.env` set `USE_MQTT_REALTIME=true`.
2. Attach the following to the Cognito Identity Pool **unauthenticated**
   role:
   ```json
   {
     "Effect": "Allow",
     "Action": ["iot:Connect", "iot:Subscribe", "iot:Receive"],
     "Resource": "*"
   }
   ```
3. Finish the SigV4 WebSocket URL signing in
   `lib/services/mqtt_service.dart` (search for `TODO(phase2)`).
4. Restart the app. MQTT messages arrive via
   `sensorService.ingestExternal()` with sub-second latency; the ring
   buffer deduplicates by timestamp so the chart does not double-plot.

---

## Project structure

```
lib/
├── app.dart                  # MaterialApp + GoRouter + bottom nav
├── main.dart                 # dotenv load + ProviderScope
├── config/env.dart           # typed env vars
├── theme/app_theme.dart      # dark theme + risk colours
├── models/
│   ├── sensor_reading.dart
│   ├── shipment.dart
│   ├── storage_centre.dart
│   ├── alert.dart
│   └── incident_log.dart
├── services/
│   ├── cognito_service.dart      # guest credential fetch + refresh
│   ├── api_service.dart          # Dio + SigV4-signed requests
│   ├── sensor_service.dart       # 5s polling + ring buffer + staleness
│   ├── mqtt_service.dart         # PHASE 2 stub — feature-flagged
│   ├── risk_engine.dart          # spoilage risk calculation
│   ├── optimisation_service.dart # centre ranking
│   ├── location_service.dart     # GPS + permissions
│   └── notification_service.dart
├── providers/                # Riverpod state
├── screens/
│   ├── onboarding/start_trip_screen.dart
│   ├── trip/trip_screen.dart
│   ├── alerts/alert_screen.dart
│   ├── map/map_screen.dart
│   └── log/log_screen.dart
├── widgets/
└── utils/
    ├── constants.dart
    ├── extensions.dart
    └── sigv4_interceptor.dart
```

---

## Risk engine

The app grades spoilage risk as a value in `[0, 1]`:

```
safe_min = 2.0 °C
safe_max = 8.0 °C
max_safe_minutes = 30

time_factor = clamp(time_outside_range_minutes / max_safe_minutes, 0, 1)
deviation   = temp < safe_min  ? (safe_min - temp) / safe_min
            : temp > safe_max  ? (temp - safe_max) / (15 - safe_max)
            : 0.0
risk_score  = clamp(time_factor * 0.6 + deviation * 0.4, 0, 1)

  0.00 – 0.30  → LOW
  0.30 – 0.65  → MEDIUM
  0.65 – 0.85  → HIGH
  0.85 – 1.00  → CRITICAL
```

See `lib/services/risk_engine.dart`.

---

## Phase 2 backlog

- [ ] Finish SigV4 presigned-URL WebSocket signing in `mqtt_service.dart`
- [ ] Migrate `ShipmentController` from in-memory to Hive-backed
- [ ] Replace unauthenticated Cognito with a User Pool (per-rider login)
- [ ] Persist reading history and incident log to Hive so trips survive
      app-kill
- [ ] `flutter_background_service` job for continued monitoring when the
      app is backgrounded
- [ ] Turn-by-turn routing via Google Directions API when a divert is
      accepted
- [ ] Offline banner with last-sync timestamp driven by Hive cache

---

## Troubleshooting

**App stuck on "Start Trip" screen.** The router redirects to `/start`
until a trip is started. Fill the form and tap **START TRIP**.

**`StateError: Missing required env var "..."`.** Your `.env` is
incomplete. Copy from `.env.example` and fill in every value.

**`401 Unauthorized` from API Gateway.** The Cognito unauth role is
missing `execute-api:Invoke`, or the ARN in the policy does not match
your deployed stage.

**"Sensor disconnected" banner.** No new reading in 15 seconds. Check
the ESP32 is publishing to IoT Core and the readings Lambda is writing
to DynamoDB.

**Google Maps blank grey tiles.** API key not set, or the Maps SDK is
not enabled on the Google Cloud project.
