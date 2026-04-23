# ColdTrack — Control Centre Dashboard

Real-time web dashboard for operations staff monitoring live vaccine cold chain
shipments across **London**. Sits alongside the existing Flutter mobile app
(`/mobile/coldtrack`) and shares the same AWS backend (IoT Core → Lambda →
DynamoDB, exposed via API Gateway, region `eu-west-2`).

Operators use this dashboard to:

1. See at a glance whether any shipment is in trouble
2. Identify which batch/rider is affected
3. Know if the rider has already responded to an alert
4. Call or escalate if the rider hasn't responded within 2 minutes
5. Confirm the shipment outcome when the trip ends

---

## Local dev setup

```bash
cd web
npm install
cp .env.example .env        # then fill in your Google Maps key at minimum
npm run dev                 # http://localhost:5173
```

The dashboard ships with mock data turned **on** (`VITE_USE_MOCK_DATA=true`),
so you can run the UI without any AWS setup. 8 realistic shipments, 12 vaccine
batches, 6 alert records (2 active, 4 historical) are loaded from
`src/mock/mockData.ts`. Polling is fully wired — open the browser console and
watch the React Query devtools to see real 5-second cycles.

### Scripts

| Command | What it does |
| --- | --- |
| `npm run dev` | Vite dev server with HMR |
| `npm run build` | Type-check + production build into `dist/` |
| `npm run preview` | Serve the production build locally |
| `npm run typecheck` | `tsc --noEmit` only |

---

## AWS setup checklist

The dashboard is designed to run against the **same Cognito Identity Pool as
the mobile app**. If the mobile app authenticates today, the dashboard will
authenticate today.

1. Identity Pool
   - Ensure `eu-west-2:<pool-id>` has unauthenticated access enabled
   - Grab the Pool ID → `VITE_COGNITO_IDENTITY_POOL_ID`
2. IAM role for unauth identities
   - Must have `execute-api:Invoke` against your API Gateway stage ARN
   - Same role the mobile app uses — no new role is required
3. API Gateway
   - Enable IAM (SigV4) auth on the resource methods listed in
     [API endpoint contract](#api-endpoint-contract) below
   - CORS: allow the dashboard's origin (`http://localhost:5173` for dev, plus
     your production origin). Allow headers: `Authorization, Content-Type,
     X-Amz-Date, X-Amz-Security-Token, X-Amz-Content-Sha256`
4. Google Maps JavaScript API
   - Enable **Maps JavaScript API** on your GCP project
   - Create an API key restricted to your HTTP referrers
   - → `VITE_GOOGLE_MAPS_API_KEY`

---

## Connecting to the real API

The **one file** to change is `src/lib/apiClient.ts`: set
`VITE_USE_MOCK_DATA=false` in your `.env` and populate
`VITE_API_GATEWAY_BASE_URL`. The mock branch is a guard at the top of every
method in the `api` object — disabling the flag sends all reads through
the axios instance and the SigV4 interceptor.

No other file imports mock data. Views, hooks, and stores already read from
`api.*`. There is no fallback-to-mock on error — if the backend is down, the
dashboard surfaces a red "Disconnected" pill in the top bar so the operator
knows not to trust the state.

---

## Activating WebSocket mode (Phase 2)

The polling loop (React Query, 5-second interval) works against any HTTP
backend. To flip to push-based updates:

1. Deploy an API Gateway WebSocket API that emits three event types:
   - `fleet:update` — any shipment changed; client re-fetches `/fleet/active`
   - `alert:new` — any new alert; client re-fetches `/alerts/active`
   - `shipment:update` with payload `{ id }` — single shipment changed
2. In `.env`:
   ```
   VITE_USE_WEBSOCKET=true
   VITE_WS_ENDPOINT=wss://xxxxxxxxxx.execute-api.eu-west-2.amazonaws.com/prod
   ```
3. No code changes needed. `src/hooks/useWebSocket.ts` is mounted at the app
   root in `App.tsx` and is a no-op when the flag is off.

Polling continues to run alongside the WS hook — this is intentional. The WS
just invalidates React Query caches, which triggers a refetch. If the WS
drops, polling continues at 5 seconds. No split-brain.

---

## Activating operator auth (Phase 2)

Guest access works for Phase 1 because the Identity Pool scopes IAM via the
unauth role. For per-operator login:

1. Create a Cognito User Pool + App Client
2. Wire the Identity Pool to accept the User Pool as an identity provider
3. In `.env`:
   ```
   VITE_REQUIRE_AUTH=true
   VITE_COGNITO_USER_POOL_ID=eu-west-2_xxxxxxxxx
   VITE_COGNITO_USER_POOL_CLIENT_ID=xxxxxxxxxxxxxxxxxxxxxxxxxx
   ```
4. Build a `LoginPage` component (stub TODO in `App.tsx`) that uses
   `aws-amplify/auth.signIn`. `cognitoAuth.ts` already accepts the User Pool
   fields — no change to the signing pipeline.

---

## API endpoint contract

All endpoints are SigV4-signed and served by API Gateway. Lambda functions
must return JSON matching the TypeScript interfaces in `src/types/*.ts`.

| Method | Path | Returns |
| --- | --- | --- |
| GET | `/fleet/active` | `Shipment[]` (only `status: 'active'`) |
| GET | `/shipments/:id` | `Shipment` including `temperatureHistory` |
| GET | `/batches` | `VaccineBatch[]` (supports query filters) |
| GET | `/batches/:batchId` | `VaccineBatch` |
| POST | `/batches` | Created `VaccineBatch` |
| PATCH | `/batches/:batchId` | Updated `VaccineBatch` |
| GET | `/alerts/active` | `Alert[]` (status `active`) |
| GET | `/alerts` | `Alert[]` — query params `from`, `to`, `riskLevel`, `shipmentId`, `batchId` |
| PATCH | `/alerts/:alertId` | Updated `Alert` |
| POST | `/incidents` | `204 No Content` |
| GET | `/riders` | `Rider[]` |

**Timestamps**: all ISO 8601 with timezone (`2024-04-23T12:05:31.000Z`).
**Numeric precision**: temperatures to one decimal; risk scores `0.0 – 1.0`.
**Risk level enum**: `'safe' | 'warning' | 'high' | 'critical'` exactly —
case-sensitive.
**CORS**: expose all the SigV4 headers listed in the AWS checklist.

---

## Deployment

### Option A — S3 + CloudFront (recommended)

```bash
npm run build
aws s3 sync dist/ s3://<your-bucket>/ --delete
aws cloudfront create-invalidation --distribution-id <id> --paths '/*'
```

- S3 bucket: static website hosting off; CloudFront serves with OAI/OAC
- CloudFront: default behaviour caches `/assets/*` aggressively, caches
  `index.html` for 0 seconds. Add a custom error response mapping 403/404 →
  `/index.html` so React Router deep links work.
- CSP: `default-src 'self'; connect-src 'self' https://*.amazonaws.com
  https://maps.googleapis.com; script-src 'self' https://maps.googleapis.com;
  img-src 'self' data: https://maps.gstatic.com https://*.googleapis.com;
  style-src 'self' 'unsafe-inline' https://fonts.googleapis.com;
  font-src 'self' https://fonts.gstatic.com;`

### Option B — AWS Amplify Hosting

1. `amplify init` in this folder
2. Build settings:
   ```yaml
   version: 1
   frontend:
     phases:
       preBuild:
         commands: [npm ci]
       build:
         commands: [npm run build]
     artifacts:
       baseDirectory: dist
       files: ['**/*']
     cache:
       paths: [node_modules/**/*]
   ```
3. Add env vars in the Amplify console (same names as `.env.example`)
4. Rewrites: `/<*>` → `/index.html` with 200 (SPA fallback)

---

## Project layout

```
src/
├── config/env.ts              Typed env wrapper
├── lib/
│   ├── apiClient.ts           Axios + mock short-circuit + SigV4 interceptor
│   ├── cognitoAuth.ts         Amplify guest creds, in-memory cache
│   ├── sigv4.ts               Browser SigV4 signer (SubtleCrypto)
│   └── haversine.ts
├── types/                     Shipment / Batch / Alert / Rider / StorageCentre
├── mock/mockData.ts           Deterministic dev data
├── store/                     Zustand: shipments, alerts, UI
├── hooks/                     React Query polling + WebSocket stub
├── components/
│   ├── layout/                Sidebar, TopBar, AlertsPanel (right, always visible)
│   ├── map/                   FleetMap + RiderMarker + StorageCentreMarker
│   ├── shipments/             Table, Row, Detail panel
│   ├── batches/               Table, Detail modal, Registration modal, VVM badge
│   ├── charts/                Sparkline (SVG), FullChart (Recharts)
│   ├── alerts/                AlertFeedItem, AlertActionButtons
│   └── ui/                    RiskBadge, StatusPill, CountdownTimer, ConnectionStatus
└── views/                     FleetOverview, BatchRegistry, AlertHistory, ShipmentDetail
```

The right-side Alerts panel is mounted in `App.tsx` and renders regardless of
the active view — it never collapses. The shipment detail panel slides in over
the top without navigating away from the map.
