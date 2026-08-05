/// Build-time configuration.
///
/// Supplied with `--dart-define`, e.g.
///
/// ```
/// flutter run --dart-define=SHOHOJ_WORKER_URL=https://worker.example.workers.dev
/// ```
///
/// There is deliberately no default. A hardcoded production URL would mean a
/// debug build silently writing to the live corpus, and a wrong guess would
/// fail at runtime with a confusing network error rather than an obvious
/// missing-config one.
class AppConfig {
  const AppConfig._();

  static const String workerUrl = String.fromEnvironment('SHOHOJ_WORKER_URL');

  /// Whether Worker-backed features can be used at all.
  ///
  /// Callers should gate their UI on this rather than letting a request fail:
  /// an unconfigured build should say so, not look broken.
  static bool get hasWorker => workerUrl.isNotEmpty;

  /// [workerUrl] without a trailing slash, so paths can be appended directly.
  static String get workerBase =>
      workerUrl.endsWith('/') ? workerUrl.substring(0, workerUrl.length - 1) : workerUrl;
}
