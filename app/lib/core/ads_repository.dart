/// House ad placements and tracking (SRS FR-10.1–FR-10.6, API §6.8).
import 'api_client.dart';

class AdPlacement {
  AdPlacement({
    required this.id,
    required this.slug,
    required this.title,
    required this.body,
    required this.ctaText,
    required this.ctaUrl,
    required this.surface,
    required this.adFormat,
    this.sponsorName,
  });

  factory AdPlacement.fromJson(Map<String, dynamic> json) => AdPlacement(
        id: json['id'] as String,
        slug: json['slug'] as String,
        title: json['title'] as String,
        body: json['body'] as String? ?? '',
        ctaText: json['cta_text'] as String? ?? '',
        ctaUrl: json['cta_url'] as String? ?? '',
        surface: json['surface'] as String,
        adFormat: json['ad_format'] as String,
        sponsorName: json['sponsor_name'] as String?,
      );

  final String id;
  final String slug;
  final String title;
  final String body;
  final String ctaText;
  final String ctaUrl;
  final String surface;
  final String adFormat;
  final String? sponsorName;

  bool get isBanner => adFormat == 'banner';
  bool get isNative => adFormat == 'native';
  bool get isInterstitial => adFormat == 'interstitial';
  bool get isRewarded => adFormat == 'rewarded';
}

class AdPlacementsResult {
  AdPlacementsResult({required this.placements, required this.adsFree});

  final List<AdPlacement> placements;
  final bool adsFree;
}

class AdsRepository {
  AdsRepository(this._client);

  final ApiClient _client;

  Future<AdPlacementsResult> fetchPlacements({
    required String surface,
    String? adFormat,
    String? sessionKey,
  }) async {
    final query = <String, String>{'surface': surface};
    if (adFormat != null) query['ad_format'] = adFormat;
    if (sessionKey != null && sessionKey.isNotEmpty) {
      query['session_key'] = sessionKey;
    }
    final json = await _client.get(
      '/ads/placements',
      queryParameters: query,
    ) as Map<String, dynamic>;
    return AdPlacementsResult(
      placements: (json['results'] as List)
          .map((e) => AdPlacement.fromJson(e as Map<String, dynamic>))
          .toList(),
      adsFree: json['ads_free'] as bool? ?? false,
    );
  }

  Future<bool> recordImpression({
    required String placementId,
    required String surface,
    required String adFormat,
    String? sessionKey,
  }) async {
    final json = await _client.post('/ads/impressions', {
      'placement_id': placementId,
      'surface': surface,
      'ad_format': adFormat,
      if (sessionKey != null) 'session_key': sessionKey,
    }, authenticated: true) as Map<String, dynamic>;
    return json['recorded'] as bool? ?? false;
  }

  Future<void> recordClick(String placementId) async {
    await _client.post('/ads/clicks', {
      'placement_id': placementId,
    }, authenticated: true);
  }
}