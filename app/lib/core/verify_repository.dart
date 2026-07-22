import 'api_client.dart';

class VerifiedProduct {
  VerifiedProduct({
    required this.name,
    required this.brand,
    this.imageUrl,
    required this.ingredientsText,
    required this.allergens,
    required this.traces,
    required this.nutriments,
    this.nutriscoreGrade,
    required this.categories,
    this.quantity,
  });

  factory VerifiedProduct.fromJson(Map<String, dynamic> json) =>
      VerifiedProduct(
        name: json['name'] as String? ?? '',
        brand: json['brand'] as String? ?? '',
        imageUrl: json['image_url'] as String?,
        ingredientsText: json['ingredients_text'] as String? ?? '',
        allergens: (json['allergens'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
        traces: (json['traces'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
        nutriments: Map<String, dynamic>.from(
          json['nutriments'] as Map? ?? {},
        ),
        nutriscoreGrade: json['nutriscore_grade'] as String?,
        categories: (json['categories'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
        quantity: json['quantity'] as String?,
      );

  final String name;
  final String brand;
  final String? imageUrl;
  final String ingredientsText;
  final List<String> allergens;
  final List<String> traces;
  final Map<String, dynamic> nutriments;
  final String? nutriscoreGrade;
  final List<String> categories;
  final String? quantity;

  Map<String, dynamic> toJson() => {
        'name': name,
        'brand': brand,
        'image_url': imageUrl,
        'ingredients_text': ingredientsText,
        'allergens': allergens,
        'traces': traces,
        'nutriments': nutriments,
        'nutriscore_grade': nutriscoreGrade,
        'categories': categories,
        'quantity': quantity,
      };
}

class VerificationScore {
  VerificationScore({
    required this.level,
    required this.reasons,
    required this.matchedAllergens,
    required this.traceMatches,
  });

  factory VerificationScore.fromJson(Map<String, dynamic> json) =>
      VerificationScore(
        level: json['level'] as String? ?? 'unknown',
        reasons: (json['reasons'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
        matchedAllergens: (json['matched_allergens'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
        traceMatches: (json['trace_matches'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      );

  final String level;
  final List<String> reasons;
  final List<String> matchedAllergens;
  final List<String> traceMatches;

  Map<String, dynamic> toJson() => {
        'level': level,
        'reasons': reasons,
        'matched_allergens': matchedAllergens,
        'trace_matches': traceMatches,
      };
}

class VerifyResult {
  VerifyResult({
    required this.gtin,
    required this.status,
    this.product,
    required this.openFoodFacts,
    required this.shoppaCatalogue,
    this.shoppaProductId,
    required this.verification,
    required this.cached,
    this.fetchedAt,
    required this.disclaimer,
    this.offline = false,
  });

  factory VerifyResult.fromJson(
    Map<String, dynamic> json, {
    bool offline = false,
  }) {
    final sources = json['sources'] as Map<String, dynamic>? ?? {};
    final productRaw = json['product'];
    return VerifyResult(
      gtin: json['gtin'] as String? ?? '',
      status: json['status'] as String? ?? 'unknown',
      product: productRaw is Map
          ? VerifiedProduct.fromJson(Map<String, dynamic>.from(productRaw))
          : null,
      openFoodFacts: sources['open_food_facts'] == true,
      shoppaCatalogue: sources['shoppa_catalogue'] == true,
      shoppaProductId: sources['shoppa_product_id'] as String?,
      verification: VerificationScore.fromJson(
        Map<String, dynamic>.from(
          json['verification'] as Map? ?? {},
        ),
      ),
      cached: json['cached'] == true,
      fetchedAt: json['fetched_at'] as String?,
      disclaimer: json['disclaimer'] as String? ??
          'Not medical advice. Always check the physical packaging.',
      offline: offline,
    );
  }

  final String gtin;
  final String status;
  final VerifiedProduct? product;
  final bool openFoodFacts;
  final bool shoppaCatalogue;
  final String? shoppaProductId;
  final VerificationScore verification;
  final bool cached;
  final String? fetchedAt;
  final String disclaimer;
  final bool offline;

  Map<String, dynamic> toJson() => {
        'gtin': gtin,
        'status': status,
        'product': product?.toJson(),
        'sources': {
          'open_food_facts': openFoodFacts,
          'shoppa_catalogue': shoppaCatalogue,
          'shoppa_product_id': shoppaProductId,
        },
        'verification': verification.toJson(),
        'cached': cached,
        'fetched_at': fetchedAt,
        'disclaimer': disclaimer,
      };
}

class AllergenOption {
  AllergenOption({required this.code, required this.label});

  factory AllergenOption.fromJson(Map<String, dynamic> json) => AllergenOption(
        code: json['code'] as String,
        label: json['label'] as String,
      );

  final String code;
  final String label;
}

class AllergenProfile {
  AllergenProfile({
    required this.allergens,
    this.consentAt,
    this.updatedAt,
    required this.canonical,
  });

  factory AllergenProfile.fromJson(Map<String, dynamic> json) =>
      AllergenProfile(
        allergens: (json['allergens'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
        consentAt: json['consent_at'] as String?,
        updatedAt: json['updated_at'] as String?,
        canonical: (json['canonical'] as List<dynamic>? ?? [])
            .map((e) => AllergenOption.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );

  final List<String> allergens;
  final String? consentAt;
  final String? updatedAt;
  final List<AllergenOption> canonical;
}

class ScanHistoryEntry {
  ScanHistoryEntry({
    required this.id,
    required this.gtin,
    required this.level,
    required this.productName,
    required this.scannedAt,
  });

  factory ScanHistoryEntry.fromJson(Map<String, dynamic> json) =>
      ScanHistoryEntry(
        id: json['id'] as String? ?? '',
        gtin: json['gtin'] as String? ?? '',
        level: json['level'] as String? ?? '',
        productName: json['product_name'] as String? ?? '',
        scannedAt: json['scanned_at'] as String? ?? '',
      );

  final String id;
  final String gtin;
  final String level;
  final String productName;
  final String scannedAt;
}

class VerifyRepository {
  VerifyRepository(this._client);

  final ApiClient _client;

  Future<VerifyResult> verify(String gtin) async {
    final json = await _client.get(
      '/products/verify',
      queryParameters: {'gtin': gtin},
    );
    return VerifyResult.fromJson(Map<String, dynamic>.from(json as Map));
  }

  Future<VerifyResult> refresh(String gtin) async {
    final json = await _client.post(
      '/products/verify/refresh',
      {'gtin': gtin},
      authenticated: true,
    );
    return VerifyResult.fromJson(Map<String, dynamic>.from(json as Map));
  }

  Future<AllergenProfile> fetchAllergenProfile() async {
    final json = await _client.get('/users/me/allergen-profile');
    return AllergenProfile.fromJson(Map<String, dynamic>.from(json as Map));
  }

  Future<AllergenProfile> saveAllergenProfile({
    required List<String> allergens,
    required bool consent,
  }) async {
    final json = await _client.put(
      '/users/me/allergen-profile',
      {
        'allergens': allergens,
        'consent': consent,
      },
    );
    return AllergenProfile.fromJson(Map<String, dynamic>.from(json as Map));
  }

  Future<List<ScanHistoryEntry>> fetchScanHistory({int limit = 50}) async {
    final json = await _client.get(
      '/users/me/scan-history',
      queryParameters: {'limit': '$limit'},
    );
    final map = Map<String, dynamic>.from(json as Map);
    final results = map['results'] as List<dynamic>? ?? [];
    return results
        .map((e) => ScanHistoryEntry.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> submitCorrection({
    required String gtin,
    required String field,
    String suggestedValue = '',
    String note = '',
  }) async {
    await _client.post(
      '/products/corrections',
      {
        'gtin': gtin,
        'field': field,
        'suggested_value': suggestedValue,
        'note': note,
      },
      authenticated: true,
    );
  }
}
