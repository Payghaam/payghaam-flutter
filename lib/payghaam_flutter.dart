/// Payghaam Flutter SDK.
///
/// Identify users, manage subscriptions, set tags, and track events against the
/// Payghaam engagement platform. The push layer is pluggable via [PushProvider].
library payghaam_flutter;

export 'src/config.dart';
export 'src/payghaam.dart';
export 'src/user_manager.dart';
export 'src/notifications.dart' show PushProvider, NoopPushProvider;
export 'src/native_push_provider.dart';
// ignore: deprecated_member_use_from_same_package
export 'src/apns_push_provider.dart';
export 'src/api_client.dart' show PayghaamApiException;
// Required by dart_plugin_registrant for linux/macos/windows desktop builds.
export 'payghaam_flutter_stub.dart' show PayghaamFlutterPlugin;
