/// Admin console APIs (Phase 5, web + mobile admin target).
import 'api_client.dart';

class AdminOverview {
  AdminOverview({
    required this.users,
    required this.lists,
    required this.quarantinedObservations,
    required this.stores,
    required this.activePromotions,
    required this.subscriptionsByPlan,
  });

  factory AdminOverview.fromJson(Map<String, dynamic> json) => AdminOverview(
        users: json['users'] as int,
        lists: json['lists'] as int,
        quarantinedObservations: json['quarantined_observations'] as int,
        stores: json['stores'] as int,
        activePromotions: json['active_promotions'] as int,
        subscriptionsByPlan:
            (json['subscriptions_by_plan'] as Map?)?.cast<String, dynamic>() ??
                const {},
      );

  final int users;
  final int lists;
  final int quarantinedObservations;
  final int stores;
  final int activePromotions;
  final Map<String, dynamic> subscriptionsByPlan;
}

class QuarantineItem {
  QuarantineItem({
    required this.id,
    required this.productName,
    required this.storeName,
    required this.price,
    required this.source,
  });

  factory QuarantineItem.fromJson(Map<String, dynamic> json) => QuarantineItem(
        id: json['id'] as String,
        productName: json['product_name'] as String,
        storeName: json['store_name'] as String,
        price: json['price'] as int,
        source: json['source'] as String,
      );

  final String id;
  final String productName;
  final String storeName;
  final int price;
  final String source;
}

class AdminRepository {
  AdminRepository(this._client);

  final ApiClient _client;

  Future<AdminOverview> fetchOverview() async {
    final json = await _client.get('/admin/overview') as Map<String, dynamic>;
    return AdminOverview.fromJson(json);
  }

  Future<List<QuarantineItem>> fetchQuarantineQueue() async {
    final json =
        await _client.get('/admin/moderation/quarantine') as Map<String, dynamic>;
    return (json['results'] as List)
        .map((e) => QuarantineItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> moderateObservation(String id, {required String action}) async {
    await _client.patch('/admin/moderation/quarantine/$id', {'action': action});
  }
}