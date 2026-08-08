import 'native_push_provider.dart';

/// Deprecated: use [PayghaamPushProvider], which now works on **both** iOS and
/// Android from the single plugin (no platform branch, no companion package).
@Deprecated('Use PayghaamPushProvider — one provider for iOS and Android.')
class ApnsPushProvider extends PayghaamPushProvider {
  /// Deprecated alias for [PayghaamPushProvider].
  ApnsPushProvider();

  /// Deprecated alias for [shareConfig].
  @Deprecated('Use shareConfig(...)')
  Future<void> shareConfigForExtension({
    required String appGroup,
    required String apiBase,
    required String apiKey,
    String? externalId,
  }) {
    return shareConfig(
      appGroup: appGroup,
      apiBase: apiBase,
      apiKey: apiKey,
      externalId: externalId,
    );
  }
}
