/// Delivery quote API (SRS FR-6.2, API Specification §6.5).
import 'api_client.dart';

class ShoppaDeliveryQuote {
  ShoppaDeliveryQuote({
    required this.platform,
    required this.displayName,
    required this.subtotal,
    required this.deliveryFee,
    required this.total,
    required this.etaMinutes,
    required this.availableItems,
    required this.totalItems,
    required this.orderUrl,
  });

  factory ShoppaDeliveryQuote.fromJson(Map<String, dynamic> json) =>
      ShoppaDeliveryQuote(
        platform: json['platform'] as String,
        displayName: json['display_name'] as String? ?? json['platform'] as String,
        subtotal: json['subtotal'] as int? ?? 0,
        deliveryFee: json['delivery_fee'] as int? ?? 0,
        total: json['total'] as int,
        etaMinutes: json['eta_minutes'] as int,
        availableItems: json['available_items'] as int,
        totalItems: json['total_items'] as int,
        orderUrl: json['order_url'] as String,
      );

  final String platform;
  final String displayName;
  final int subtotal;
  final int deliveryFee;
  final int total;
  final int etaMinutes;
  final int availableItems;
  final int totalItems;
  final String orderUrl;

  bool get isFullyAvailable =>
      totalItems > 0 && availableItems >= totalItems;
}

class ShoppaDeliveryQuotes {
  ShoppaDeliveryQuotes({
    required this.currencyCode,
    required this.quotes,
  });

  factory ShoppaDeliveryQuotes.fromJson(Map<String, dynamic> json) =>
      ShoppaDeliveryQuotes(
        currencyCode: json['currency_code'] as String? ?? 'ZAR',
        quotes: (json['quotes'] as List? ?? [])
            .map((e) => ShoppaDeliveryQuote.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  final String currencyCode;
  final List<ShoppaDeliveryQuote> quotes;

  bool get isEmpty => quotes.isEmpty;
}

class DeliveryRepository {
  DeliveryRepository(this._client);

  final ApiClient _client;

  Future<ShoppaDeliveryQuotes> fetchDeliveryQuotes(String listId) async {
    final json = await _client.get('/lists/$listId/delivery-quotes')
        as Map<String, dynamic>;
    return ShoppaDeliveryQuotes.fromJson(json);
  }
}