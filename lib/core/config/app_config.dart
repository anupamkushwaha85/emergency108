/// App configuration loaded from compile-time --dart-define-from-file=.env
///
/// Run with:  flutter run --dart-define-from-file=.env
/// Build with: flutter build apk --dart-define-from-file=.env
class AppConfig {
  AppConfig._();

  /// Base URL for the Spring Boot REST API (includes /api suffix)
  static const String backendUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'https://emergency-dispatch-system-x11l.onrender.com/api',
  );

  /// Base URL for WebSocket connections (no /api suffix).
  /// Automatically strips the /api suffix from backendUrl so that
  /// WsLocationService can append /ws correctly.
  static String get wsBaseUrl {
    final url = backendUrl;
    if (url.endsWith('/api')) {
      return url.substring(0, url.length - 4);
    }
    return url;
  }

  /// Google Maps / Directions API key (also set in AndroidManifest via local.properties)
  static const String googleMapsApiKey = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
    defaultValue: '',
  );
}
