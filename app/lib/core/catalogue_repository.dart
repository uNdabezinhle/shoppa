/// Catalogue / product search (M3 / FR-5.3), API Specification §6.4.
import 'api_client.dart';

class ShoppaProduct {
  ShoppaProduct({
    required this.id,
    required this.name,
    required this.region,
  });

  factory ShoppaProduct.fromJson(Map<String, dynamic> json) => ShoppaProduct(
        id: json['id'] as String,
        name: json['name'] as String,
        region: json['region'] as String? ?? 'ZA',
      );

  final String id;
  final String name;
  final String region;
}

class ProductStorePrice {
  ProductStorePrice({
    required this.storeId,
    required this.price,
    required this.confidence,
  });

  factory ProductStorePrice.fromJson(Map<String, dynamic> json) =>
      ProductStorePrice(
        storeId: json['store_id'] as String,
        price: json['price'] as int,
        confidence: json['confidence'] as String,
      );

  final String storeId;
  final int price;
  final String confidence;
}

class CatalogueRepository {
  CatalogueRepository(this._client);

  final ApiClient _client;

  Future<List<ShoppaProduct>> searchProducts(String query) async {
    final json = await _client.get(
      '/products',
      queryParameters: query.trim().isEmpty ? null : {'q': query.trim()},
    ) as Map<String, dynamic>;
    final results = json['results'] as List;
    return results
        .map((e) => ShoppaProduct.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<ProductStorePrice?> fetchStorePrice({
    required String productId,
    required String storeId,
  }) async {
    try {
      final json = await _client.get(
        '/products/$productId/store-price',
        queryParameters: {'store_id': storeId},
      ) as Map<String, dynamic>;
      return ProductStorePrice.fromJson(json);
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }
}