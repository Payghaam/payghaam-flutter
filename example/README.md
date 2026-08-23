# payghaam_example

Example app for the `payghaam_flutter` package. It demonstrates SDK
`initialize` / `login` / `trackEvent`, plus **iOS Live Activities**:

- `AppDelegate` calls `PayghaamLiveActivities.observe(DeliveryAttributes.self)`
- Local start/update/end via `payghaam/liveActivitiesLocal` (Swift
  `Activity.request` — not invented in Dart)
- Dart buttons call `PayghaamLiveActivities.startActivity` / `updateActivity` /
  `endActivity` / `refresh`

## Getting started

1. `flutter pub get` from this `example/` directory.
2. `cd ios && pod install` (Payghaam iOS ≥ 0.1.4).
3. Open `ios/Runner.xcworkspace` in Xcode; run on a **physical iPhone**
   (Live Activities / push-to-start need a device).
4. Replace `YOUR_PROJECT_ID` / `ek_client_...` / `baseUrl` in `lib/main.dart`.
5. Initialize → Login → **Start local LA**.

### Widget Extension (optional but needed for Lock Screen UI)

Swift stubs live under `ios/LiveActivity/` and `ios/Runner/DeliveryAttributes.swift`.
Add a Widget Extension target in Xcode and follow the comments in
`DeliveryLiveActivity.swift`. Without the extension, tokens still register with
Payghaam; the system UI will not appear.

### Server-driven activity

With a **REST** project key:

```bash
curl -X POST "$API/api/live-activities" \
  -H "Authorization: Bearer ek_rest_..." \
  -H "Content-Type: application/json" \
  -d '{
    "externalId": "example-user",
    "activityId": "order-4821",
    "attributesType": "DeliveryAttributes",
    "attributes": { "orderId": "4821" },
    "contentState": { "stage": "picked_up", "etaMinutes": 25 }
  }'
```

After push-to-start, tap **Allow** on the lock screen so the update token POSTs.
