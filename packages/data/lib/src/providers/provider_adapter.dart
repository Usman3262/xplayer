import 'provider_models.dart';

/// One interface for every panel protocol (Xtream, M3U, Stalker/MAC, future).
/// Screens never see the protocol: they get domain entities through the
/// mappers in `provider_mappers.dart` and the catalog layer (Phase 6).
///
/// Rules for implementations:
/// * every call has a timeout and throws [ProviderFailure] (never a raw
///   SocketException / FormatException);
/// * tolerant parsing — numbers as strings, missing fields, odd ids;
/// * big payloads are decoded off the UI thread ([ProviderHttp] does this);
/// * never log credentials or full stream URLs.
abstract class ProviderAdapter {
  ProviderKind get kind;

  ProviderCapabilities get capabilities;

  /// Login / account check. Always hits the panel (spec §3.5: never assume an
  /// account is still active). Throws [ProviderFailure] with
  /// `unauthorized` / `expired` / `banned` / `network` / `timeout` …
  Future<ProviderAccount> authenticate();

  Future<List<ProviderCategory>> liveCategories();
  Future<List<ProviderChannel>> liveChannels({String? categoryId});

  /// Empty when [ProviderCapabilities.movies] is false.
  Future<List<ProviderCategory>> movieCategories();
  Future<List<ProviderMovie>> movies({String? categoryId});
  Future<ProviderMovieDetails> movieDetails(String movieId);

  /// Empty when [ProviderCapabilities.series] is false.
  Future<List<ProviderCategory>> seriesCategories();
  Future<List<ProviderSeries>> series({String? categoryId});
  Future<ProviderSeriesDetails> seriesDetails(String seriesId);

  /// Now/next and a few upcoming programmes for one channel. Empty when the
  /// panel has no EPG for it.
  Future<List<EpgEntry>> shortEpg(ProviderChannel channel, {int limit = 4});

  /// Turns a [StreamRef] into a playable URL right before playback (Stalker
  /// links are short-lived). The result holds credentials: player only.
  Future<ResolvedStream> resolveStream(StreamRef ref);

  /// Closes the HTTP client / cancels in-flight work.
  void dispose();
}

/// Builds the adapter for saved credentials. Each protocol registers itself in
/// later steps (5.2 Xtream, 5.3 M3U, 5.4 Stalker); an unregistered kind throws
/// `unsupported` so the UI can say "this panel type isn't available yet".
class ProviderAdapterFactory {
  ProviderAdapterFactory._();

  static final Map<ProviderKind, ProviderAdapter Function(ProviderCredentials)> _builders = {};

  static void register(
    ProviderKind kind,
    ProviderAdapter Function(ProviderCredentials credentials) builder,
  ) =>
      _builders[kind] = builder;

  static bool supports(ProviderKind kind) => _builders.containsKey(kind);

  static ProviderAdapter create(ProviderCredentials credentials) {
    final problems = credentials.validate();
    if (problems.isNotEmpty) {
      throw ProviderFailure(
        ProviderFailureKind.invalidInput,
        problems.keys.join(','),
      );
    }
    final build = _builders[credentials.kind];
    if (build == null) {
      throw ProviderFailure(ProviderFailureKind.unsupported, credentials.kind.name);
    }
    return build(credentials);
  }
}
