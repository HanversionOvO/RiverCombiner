import 'package:flutter/services.dart';

/// iOS 26+ Native Tab Bar with Search Support
///
/// This widget enables the native iOS 26 tab bar with search functionality.
/// When enabled, it replaces the Flutter app's root with a native UITabBarController.
///
/// **Important**: This is an experimental API and may significantly impact your app's
/// navigation structure. Use with caution.
///
/// Example:
/// ```dart
/// @override
/// void initState() {
///   super.initState();
///   IOS26NativeSearchTabBar.enable(
///     tabs: [
///       NativeTabConfig(title: 'Home', sfSymbol: 'house.fill'),
///       NativeTabConfig(title: 'Search', sfSymbol: 'magnifyingglass', isSearchTab: true),
///       NativeTabConfig(title: 'Profile', sfSymbol: 'person.fill'),
///     ],
///     onTabSelected: (index) {
///       print('Tab selected: $index');
///     },
///     onSearchQueryChanged: (query) {
///       print('Search query: $query');
///     },
///   );
/// }
/// ```
class IOS26NativeSearchTabBar {
  static const MethodChannel _channel = MethodChannel(
    'adaptive_platform_ui/native_tab_bar',
  );

  static bool _isEnabled = false;

  /// Enable native tab bar mode
  ///
  /// This will replace your app's root view controller with a native
  /// UITabBarController. Your Flutter content will be displayed within
  /// the selected tab.
  static Future<void> enable({
    required List<NativeTabConfig> tabs,
    int selectedIndex = 0,
    int? tint,
    int? unselectedItemTint,
    void Function(int index)? onTabSelected,
    void Function(String query)? onSearchQueryChanged,
    void Function(String query)? onSearchSubmitted,
    VoidCallback? onSearchCancelled,
  }) async {
    if (_isEnabled) {
      return;
    }

    // Setup method call handler for callbacks
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onTabSelected':
          final index = call.arguments['index'] as int;
          onTabSelected?.call(index);
          break;
        case 'onSearchQueryChanged':
          final query = call.arguments['query'] as String;
          onSearchQueryChanged?.call(query);
          break;
        case 'onSearchSubmitted':
          final query = call.arguments['query'] as String;
          onSearchSubmitted?.call(query);
          break;
        case 'onSearchCancelled':
          onSearchCancelled?.call();
          break;
      }
    });

    // Enable native tab bar
    final payload = <String, dynamic>{
      'tabs': tabs
          .map(
            (tab) => {
              'title': tab.title,
              'sfSymbol': tab.sfSymbol,
              'isSearch': tab.isSearchTab,
              'badgeCount': tab.badgeCount,
            },
          )
          .toList(),
      'selectedIndex': selectedIndex,
      'tint': tint,
      'unselectedItemTint': unselectedItemTint,
    }..removeWhere((_, value) => value == null);
    await _channel.invokeMethod('enableNativeTabBar', payload);

    _isEnabled = true;
  }

  /// Disable native tab bar and return to Flutter-only mode
  static Future<void> disable() async {
    if (!_isEnabled) {
      return;
    }

    await _channel.invokeMethod('disableNativeTabBar');
    _isEnabled = false;
  }

  /// Set the selected tab index
  static Future<void> setSelectedIndex(int index) async {
    await _channel.invokeMethod('setSelectedIndex', {'index': index});
  }

  /// Show the search bar (activates the search controller)
  static Future<void> showSearch() async {
    await _channel.invokeMethod('showSearch');
  }

  /// Hide the search bar
  static Future<void> hideSearch() async {
    await _channel.invokeMethod('hideSearch');
  }

  /// Update tab bar visual style.
  static Future<void> setStyle({int? tint, int? unselectedItemTint}) async {
    final payload = <String, dynamic>{};
    if (tint != null) {
      payload['tint'] = tint;
    }
    if (unselectedItemTint != null) {
      payload['unselectedItemTint'] = unselectedItemTint;
    }
    if (payload.isEmpty) {
      return;
    }
    await _channel.invokeMethod('setStyle', payload);
  }

  /// Show or hide native tab bar while keeping native search mode enabled.
  static Future<void> setTabBarHidden(
    bool hidden, {
    bool animated = true,
  }) async {
    await _channel.invokeMethod('setTabBarHidden', {
      'hidden': hidden,
      'animated': animated,
    });
  }

  /// Update tab badge counts.
  static Future<void> setBadgeCounts(List<int?> badgeCounts) async {
    await _channel.invokeMethod('setBadgeCounts', {'badgeCounts': badgeCounts});
  }

  /// Check if native tab bar is currently enabled
  static Future<bool> isEnabled() async {
    try {
      final result = await _channel.invokeMethod<bool>('isEnabled');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }
}

/// Configuration for a native tab
class NativeTabConfig {
  /// The title of the tab
  final String title;

  /// SF Symbol name for the tab icon (iOS only)
  final String? sfSymbol;

  /// Whether this tab is a search tab
  ///
  /// Only one tab should be marked as a search tab.
  /// When selected, the tab bar will transform into a search bar on iOS 26+.
  final bool isSearchTab;

  /// Optional badge count displayed on tab item.
  final int? badgeCount;

  const NativeTabConfig({
    required this.title,
    this.sfSymbol,
    this.isSearchTab = false,
    this.badgeCount,
  });
}
