/// Subscription plans and billing (SRS FR-9.1–FR-9.2, API §6.7).
import 'api_client.dart';

class ShoppaPlan {
  ShoppaPlan({
    required this.slug,
    required this.name,
    required this.priceMonthly,
    required this.currencyCode,
    required this.features,
    this.maxOwnedLists,
  });

  factory ShoppaPlan.fromJson(Map<String, dynamic> json) => ShoppaPlan(
        slug: json['slug'] as String,
        name: json['name'] as String,
        priceMonthly: json['price_monthly'] as int,
        currencyCode: json['currency_code'] as String? ?? 'ZAR',
        features: (json['features'] as List? ?? [])
            .map((e) => e as String)
            .toList(),
        maxOwnedLists: json['max_owned_lists'] as int?,
      );

  final String slug;
  final String name;
  final int priceMonthly;
  final String currencyCode;
  final List<String> features;
  final int? maxOwnedLists;

  bool get isFree => priceMonthly <= 0;
}

class ShoppaSubscription {
  ShoppaSubscription({
    required this.plan,
    required this.status,
    required this.featureFlags,
    this.currentPeriodEnd,
  });

  factory ShoppaSubscription.fromJson(Map<String, dynamic> json) =>
      ShoppaSubscription(
        plan: ShoppaPlan.fromJson(json['plan'] as Map<String, dynamic>),
        status: json['status'] as String,
        featureFlags: (json['feature_flags'] as List? ?? [])
            .map((e) => e as String)
            .toList(),
        currentPeriodEnd: json['current_period_end'] as String?,
      );

  final ShoppaPlan plan;
  final String status;
  final List<String> featureFlags;
  final String? currentPeriodEnd;

  bool hasFeature(String feature) => featureFlags.contains(feature);
}

class CheckoutSession {
  CheckoutSession({
    required this.checkoutUrl,
    required this.planId,
    this.devMode = false,
  });

  factory CheckoutSession.fromJson(Map<String, dynamic> json) => CheckoutSession(
        checkoutUrl: json['checkout_url'] as String,
        planId: json['plan_id'] as String,
        devMode: json['dev_mode'] as bool? ?? false,
      );

  final String checkoutUrl;
  final String planId;
  final bool devMode;
}

class SubscriptionsRepository {
  SubscriptionsRepository(this._client);

  final ApiClient _client;

  Future<List<ShoppaPlan>> fetchPlans() async {
    final json = await _client.get('/subscriptions/plans') as Map<String, dynamic>;
    return (json['results'] as List)
        .map((e) => ShoppaPlan.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<ShoppaSubscription> fetchMySubscription() async {
    final json =
        await _client.get('/subscriptions/me') as Map<String, dynamic>;
    return ShoppaSubscription.fromJson(json);
  }

  Future<CheckoutSession> startCheckout(String planId) async {
    final json = await _client.post('/subscriptions/checkout', {
      'plan_id': planId,
    }) as Map<String, dynamic>;
    return CheckoutSession.fromJson(json);
  }
}