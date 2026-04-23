# ColdTrack Rider — Progressive Web App

Progressive web app for vaccine cold-chain couriers. Runs on a phone mounted
to a motorbike handlebar; designed to be glanceable at 60 km/h through a
visor, with one gloved thumb. It is the **rider-facing counterpart** to the
Control Centre dashboard at `/web`.

The rider and the operator see two sides of the same event: when the rider
taps **Accept** on an alert here, the operator's dashboard flips from pulsing
amber to green within the next poll cycle. Same backend, same data shapes,
same design language.

---

## Local dev setup

```bash
cd mobile/coldtrack-pwa
npm install
cp .env.example .env           # defaults run fully mocked — no AWS needed
npm run dev                    # http://localhost:5174
```

Mocks are on by default (`VITE_USE_MOCK_DATA=true`). No AWS credentials
required. To view on a phone on the same LAN, `npm run dev` exposes the
server at `http://<your-ip>:5174` — but note that device APIs (wake lock,
geolocation, web push, service worker) require HTTPS in production. Use
`npm run build && npm run preview` over `https` for full-fidelity testing.

---

## Jake Fletcher demo walkthrough (40 seconds, no AWS)

With the defaults from `.env.example`, a cold `npm run dev` plays the full
scenario end-to-end:

| T (s) | Event                                                                                           |
| ----- | ----------------------------------------------------------------------------------------------- |
|   0   | Open `/` — redirects to Login. Tap **Continue as Jake Fletcher**.                               |
|   2   | Assignments screen — one row (YFV-2024-UK-0008 Yellow Fever, 300 doses). Tap it.                |
|   4   | Manifest. Tap **Scan QR** → camera opens; tap the batch ID to auto-verify (mock mode).          |
|   6   | Temp at loading reads 4.2°C ✓. Tap **Start trip**.                                              |
|   8   | Live Trip: gauge green, map shows rider pin near King's College, dashed route to Woolwich.     |
|  15   | Temp drifts upward. Banner tints amber at ~6.3°C, rider feels a brief haptic tick.             |
|  30   | HIGH alert fires at 8.4°C. Full-bleed red takeover, voice speaks, phone vibrates.              |
|  35   | Tap **✓ Accept** → navigates to Diversion Nav, pointing at King's College Cold Store.          |
|  37   | Mock map ticks the rider inside the cold-store bubble. Tap **✓ I've arrived**.                 |
|  38   | Cold-store handoff form. Fill in recipient name, tap **Confirm handoff**.                     |
|  40   | Trip Summary: "Diverted to King's — 300 doses saved", full temp trace with excursion shaded.  |

The mock transport's temperature curve mirrors the dashboard's
`seriesExcursion` helper so the chart on this Summary screen is visually
identical to what the operator sees on `/web`.

---

## How this PWA shares the backend with `/web`

Both apps talk to the same API Gateway + Cognito Identity Pool + Timestream
backend. `src/lib/sigv4.ts` and `src/lib/cognitoAuth.ts` are copied verbatim
from `/web/src/lib/*`; any change to the SigV4 signer must land in both or
the apps drift.

Types are also duplicated from `/web/src/types/*` with no renames:

```
web/src/types/shipment.ts      →  src/types/shipment.ts
web/src/types/batch.ts         →  src/types/batch.ts
web/src/types/alert.ts         →  src/types/alert.ts
web/src/types/rider.ts         →  src/types/rider.ts
web/src/types/storageCentre.ts →  src/types/storageCentre.ts
```

Rider-only extensions (`MyAssignment`, `HandoffRecord`, `PositionPing`)
live in `src/types/rider-ext.ts`.

### Endpoints

Shared:

```
PATCH /alerts/:alertId           update riderResponse, operatorNotes
POST  /incidents                 log an event to the shipment timeline
PATCH /batches/:batchId          update batch status after handoff
```

New rider-only:

```
GET   /riders/me                 my profile
GET   /riders/me/shipment        my one active shipment (or null)
GET   /riders/me/assignments     today's assignments
GET   /riders/me/alerts          active alerts targeted at me
POST  /shipments/:id/start       transition to 'active'
POST  /shipments/:id/ping        { lat, lng, clientTs } position
POST  /handoffs                  HandoffRecord
POST  /rider/push/subscribe      Web Push subscription payload
```

---

## How to connect to the real API

Flip one file — `.env`:

```bash
VITE_USE_MOCK_DATA=false
VITE_COGNITO_IDENTITY_POOL_ID=eu-west-2:your-actual-id
VITE_API_GATEWAY_BASE_URL=https://xxxxxxxxxx.execute-api.eu-west-2.amazonaws.com/prod
VITE_GOOGLE_MAPS_API_KEY=your_key_here
```

`src/lib/apiClient.ts` short-circuits to the mock transport when
`VITE_USE_MOCK_DATA=true`; when false, every axios call is signed with
temporary Cognito credentials via the SigV4 interceptor.

For Phase 2 (email/password login):

```bash
VITE_REQUIRE_AUTH=true
VITE_COGNITO_USER_POOL_ID=eu-west-2_xxxxxxxxx
VITE_COGNITO_USER_POOL_CLIENT_ID=xxxxxxxxxxxxxxxxxxxxxxxxxx
```

---

## How to enable Web Push

1. Generate a VAPID keypair (e.g. `npx web-push generate-vapid-keys`).
2. Set `VITE_WEB_PUSH_PUBLIC_KEY` in `.env` to the public key.
3. Put the private key on the backend; publish push notifications to each
   subscription via `POST /rider/push/subscribe`'s payload.
4. The rider must install the PWA before the browser will accept Push on
   iOS — on Android a regular install is enough.

The service worker (`src/service-worker.ts`) handles the `push` event,
vibrates the phone, and deep-links the notification tap to `/alert`.

---

## Device API capability matrix

| Feature                | Chrome Android | Safari iOS 16.4+ | Samsung Internet | Firefox Android |
| ---------------------- | :------------: | :--------------: | :--------------: | :-------------: |
| Service Worker         |       ✓        |         ✓        |         ✓        |        ✓        |
| Web Push               |       ✓        |    ✓ (installed) |         ✓        |        ✓        |
| Wake Lock              |       ✓        |         ✓        |         ✓        |        ✗        |
| Vibration              |       ✓        |         ✗        |         ✓        |        ✓        |
| `speechSynthesis`      |       ✓        |         ✓        |         ✓        |        ✓        |
| Barcode Detection API  |       ✓        |         ✗        |         ✓        |        ✗        |
| Background Sync        |       ✓        |         ✗        |         ✓        |        ✗        |
| Screen Orientation API |       ✓        |     partial      |         ✓        |        ✓        |

Every device API call is feature-detected; missing capabilities degrade
gracefully (QR falls back to @zxing/browser, photo capture falls back to
`<input capture>`, push falls back to aggressive polling).

---

## Deployment: S3 + CloudFront

Web Push and service workers both require a secure context. The production
deployment is a static site on S3 fronted by CloudFront with an ACM cert:

```bash
npm run build                                     # emits ./dist
aws s3 sync dist/ s3://coldtrack-rider-pwa/       \
    --delete                                      \
    --cache-control "public,max-age=31536000,immutable" \
    --exclude "service-worker.js"                 \
    --exclude "index.html"                        \
    --exclude "manifest.webmanifest"

# The service worker and index.html must NEVER be cached aggressively.
aws s3 cp dist/service-worker.js s3://coldtrack-rider-pwa/service-worker.js \
    --cache-control "no-cache"
aws s3 cp dist/index.html s3://coldtrack-rider-pwa/index.html \
    --cache-control "no-cache"
aws s3 cp dist/manifest.webmanifest s3://coldtrack-rider-pwa/manifest.webmanifest \
    --cache-control "no-cache"

aws cloudfront create-invalidation --distribution-id DXXXXXXXXXXXX --paths "/index.html" "/service-worker.js" "/manifest.webmanifest"
```

CloudFront behaviour: origin is the S3 bucket, viewer protocol policy
*Redirect HTTP to HTTPS*, default root object `index.html`, custom error
response 404 → `/index.html` 200 (for SPA routing).

---

## Project structure

```
src/
├── main.tsx                              # entry
├── App.tsx                               # routes + global providers + AlertRouter
├── service-worker.ts                     # injectManifest SW (Workbox)
├── config/env.ts                         # typed env with fallbacks
├── lib/
│   ├── apiClient.ts                      # axios + sigv4 + mock transport
│   ├── cognitoAuth.ts                    # copied verbatim from /web
│   ├── sigv4.ts                          # copied verbatim from /web
│   ├── haversine.ts
│   ├── speech.ts                         # Web Speech API wrapper
│   ├── haptic.ts                         # navigator.vibrate wrapper
│   ├── wakeLock.ts                       # screen stays on
│   ├── geolocation.ts                    # watchPosition
│   ├── qrScan.ts                         # BarcodeDetector → zxing fallback
│   ├── push.ts                           # Web Push subscribe
│   └── offlineQueue.ts                   # IndexedDB write queue
├── types/                                # copied from /web + rider-ext
├── store/                                # Zustand: trip / alert / auth
├── hooks/
│   ├── useMyShipment.ts                  # 5s poll
│   ├── useMyAlerts.ts                    # 5s poll
│   ├── useMyAssignments.ts               # 30s poll
│   ├── useGeolocationReporting.ts        # 10s position ping
│   ├── useWakeLock.ts
│   └── useOnline.ts
├── components/
│   ├── layout/        StatusBar, BottomNav
│   ├── trip/          RiskGauge, TempReadout, SafeForTimer, TripMap, ConnectivityBanner
│   ├── alert/         AlertOverlay, AlertActions, AlertVoicePlayer
│   ├── handoff/       QrScanner, PhotoCapture, SignaturePad, HandoffForm
│   ├── ui/            BigButton, IconChip, VVMBadge, InstallPrompt
│   └── charts/        TemperatureFullChart (ported from /web)
├── screens/                              # 10 top-level routes
└── mock/mockData.ts                      # Jake's scenario
```

---

## Acceptance test

> The rider's **✓ Accept** tap on this PWA must visibly flip the dashboard
> AlertFeedItem at `/web` from pulsing amber to green within one poll cycle.

Run both apps with the same `VITE_API_GATEWAY_BASE_URL` pointed at the same
backend stage (or, in mocked dev, share `mockAlerts[]` via a symlinked file).
Tap Accept here; watch the dashboard flip in ≤5s.
