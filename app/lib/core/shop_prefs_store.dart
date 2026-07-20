// Lightweight shop-mode preferences (device-local).
import 'package:shared_preferences/shared_preferences.dart';

abstract class ShopPrefsStore {
  Future<bool> getSkipPricePrompt();
  Future<void> setSkipPricePrompt(bool value);

  /// Larger check targets + less chrome while shopping.
  Future<bool> getFocusShopMode();
  Future<void> setFocusShopMode(bool value);

  /// When true (default), keep the display awake in shop mode.
  Future<bool> getKeepScreenOn();
  Future<void> setKeepScreenOn(bool value);

  /// Preferred aisle walk layout id (`default`, `checkers`, …).
  /// Empty / null means auto-detect from store name.
  Future<String?> getAisleLayoutId();
  Future<void> setAisleLayoutId(String? layoutId);
}

class InMemoryShopPrefsStore implements ShopPrefsStore {
  bool _skipPrice = false;
  bool _focusShop = false;
  bool _keepScreenOn = true;
  String? _aisleLayoutId;

  @override
  Future<bool> getSkipPricePrompt() async => _skipPrice;

  @override
  Future<void> setSkipPricePrompt(bool value) async {
    _skipPrice = value;
  }

  @override
  Future<bool> getFocusShopMode() async => _focusShop;

  @override
  Future<void> setFocusShopMode(bool value) async {
    _focusShop = value;
  }

  @override
  Future<bool> getKeepScreenOn() async => _keepScreenOn;

  @override
  Future<void> setKeepScreenOn(bool value) async {
    _keepScreenOn = value;
  }

  @override
  Future<String?> getAisleLayoutId() async => _aisleLayoutId;

  @override
  Future<void> setAisleLayoutId(String? layoutId) async {
    _aisleLayoutId = (layoutId == null || layoutId.isEmpty) ? null : layoutId;
  }
}

class SharedPreferencesShopPrefsStore implements ShopPrefsStore {
  static const _skipPriceKey = 'shoppa.shop.skip_price_prompt';
  static const _focusShopKey = 'shoppa.shop.focus_mode';
  static const _keepScreenKey = 'shoppa.shop.keep_screen_on';
  static const _aisleLayoutKey = 'shoppa.shop.aisle_layout_id';

  @override
  Future<bool> getSkipPricePrompt() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_skipPriceKey) ?? false;
  }

  @override
  Future<void> setSkipPricePrompt(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_skipPriceKey, value);
  }

  @override
  Future<bool> getFocusShopMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_focusShopKey) ?? false;
  }

  @override
  Future<void> setFocusShopMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_focusShopKey, value);
  }

  @override
  Future<bool> getKeepScreenOn() async {
    final prefs = await SharedPreferences.getInstance();
    // Default on — shoppers rarely want the screen to sleep mid-aisle.
    return prefs.getBool(_keepScreenKey) ?? true;
  }

  @override
  Future<void> setKeepScreenOn(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keepScreenKey, value);
  }

  @override
  Future<String?> getAisleLayoutId() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_aisleLayoutKey);
    if (raw == null || raw.isEmpty || raw == 'auto') return null;
    return raw;
  }

  @override
  Future<void> setAisleLayoutId(String? layoutId) async {
    final prefs = await SharedPreferences.getInstance();
    if (layoutId == null || layoutId.isEmpty || layoutId == 'auto') {
      await prefs.remove(_aisleLayoutKey);
    } else {
      await prefs.setString(_aisleLayoutKey, layoutId);
    }
  }
}
