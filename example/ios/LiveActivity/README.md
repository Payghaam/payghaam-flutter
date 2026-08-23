# Live Activity Widget Extension (example stubs)

These files are **not** an Xcode target yet. Add one in Xcode:

1. File → New → Target → **Widget Extension**
2. Enable **Include Live Activity**
3. Add `DeliveryLiveActivity.swift` to the new target
4. Add `../Runner/DeliveryAttributes.swift` to **both** Runner and the extension
5. Runner Info.plist already sets `NSSupportsLiveActivities`

Until then, local `Activity.request` and Payghaam token registration still work;
Lock Screen / Dynamic Island UI will not.
