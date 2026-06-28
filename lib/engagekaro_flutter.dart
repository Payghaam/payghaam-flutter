/// EngageKaro Flutter SDK.
///
/// Identify users, manage subscriptions, set tags, and track events against the
/// EngageKaro engagement platform. The push layer is pluggable via [PushProvider].
library engagekaro_flutter;

export 'src/config.dart';
export 'src/engagekaro.dart';
export 'src/user_manager.dart';
export 'src/notifications.dart' show PushProvider, NoopPushProvider;
export 'src/apns_push_provider.dart';
export 'src/api_client.dart' show EngageKaroApiException;
