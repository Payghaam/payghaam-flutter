## 0.1.1

* Fix: an API key/base URL change (e.g. rotating a key) wasn't picked up by
  the native iOS/Android bridge until the app process was fully killed and
  relaunched — a Flutter hot restart kept the old key bound natively,
  causing "Invalid API key" 401s. `initialize()`/`login()` now await the
  native sync instead of firing it unawaited, and the native SDKs rebind
  their client whenever the key/base URL actually changes.
* Pin the native SDK dependency versions (`com.payghaam:payghaam` on
  Android, `Payghaam` on CocoaPods) instead of leaving them unconstrained.

## 0.1.0

* Initial release of the Payghaam Flutter SDK.
* User identification, tags, email/SMS subscriptions, and event tracking.
* Native push on iOS (APNs) and Android (FCM) via [PayghaamPushProvider].
* Pluggable [PushProvider] interface and consent gating.
