import 'package:flutter_test/flutter_test.dart';
import 'package:shoppa_app/core/shop_prefs_store.dart';
import 'package:shoppa_app/widgets/item_form_dialog.dart';

void main() {
  group('InMemoryShopPrefsStore', () {
    test('skip price prompt defaults false and toggles', () async {
      final store = InMemoryShopPrefsStore();
      expect(await store.getSkipPricePrompt(), isFalse);
      await store.setSkipPricePrompt(true);
      expect(await store.getSkipPricePrompt(), isTrue);
      await store.setSkipPricePrompt(false);
      expect(await store.getSkipPricePrompt(), isFalse);
    });

    test('focus shop mode defaults false and toggles', () async {
      final store = InMemoryShopPrefsStore();
      expect(await store.getFocusShopMode(), isFalse);
      await store.setFocusShopMode(true);
      expect(await store.getFocusShopMode(), isTrue);
      await store.setFocusShopMode(false);
      expect(await store.getFocusShopMode(), isFalse);
    });

    test('keep screen on defaults true and toggles', () async {
      final store = InMemoryShopPrefsStore();
      expect(await store.getKeepScreenOn(), isTrue);
      await store.setKeepScreenOn(false);
      expect(await store.getKeepScreenOn(), isFalse);
      await store.setKeepScreenOn(true);
      expect(await store.getKeepScreenOn(), isTrue);
    });

    test('aisle layout id defaults null and clears on empty', () async {
      final store = InMemoryShopPrefsStore();
      expect(await store.getAisleLayoutId(), isNull);
      await store.setAisleLayoutId('picknpay');
      expect(await store.getAisleLayoutId(), 'picknpay');
      await store.setAisleLayoutId(null);
      expect(await store.getAisleLayoutId(), isNull);
      await store.setAisleLayoutId('spar');
      await store.setAisleLayoutId('');
      expect(await store.getAisleLayoutId(), isNull);
    });
  });

  group('kCommonItemUnits', () {
    test('includes everyday grocery units', () {
      expect(kCommonItemUnits, containsAll(['ea', 'kg', 'g', 'l', 'ml', 'pack']));
    });
  });
}
