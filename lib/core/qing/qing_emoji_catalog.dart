class QingEmojiCatalog {
  static const String _assetPrefix = 'asset://assets/emoji';

  static const List<int> _emojiA = <int>[
    1135,
    1136,
    1137,
    1138,
    1139,
    1140,
    1141,
    1142,
    1143,
    1144,
    1145,
    1146,
    1147,
    1148,
    1149,
    1150,
    1151,
    1152,
    1153,
    1154,
    1155,
    1156,
    1157,
    1158,
    1159,
    1160,
    1161,
    1162,
    1163,
    1164,
    1165,
    1166,
    1167,
    1168,
    1169,
    1170,
    1171,
    1172,
    1173,
    1174,
    1175,
    1176,
    1177,
    1178,
    1179,
    1180,
    1181,
    1182,
    1183,
    1184,
    1185,
    1186,
    1187,
    1188,
    1189,
    1190,
    1191,
    1192,
    1193,
    1194,
    1195,
    1196,
  ];

  static const List<int> _emojiS2 = <int>[
    11,
    12,
    13,
    14,
    15,
    16,
    17,
    18,
    19,
    20,
    21,
    22,
    23,
    24,
    25,
    26,
    27,
    28,
    29,
    30,
    31,
    32,
    33,
    34,
    35,
    36,
    37,
    38,
    40,
    87,
    88,
    89,
    90,
  ];

  static const List<int> _emojiS3 = <int>[
    634,
    635,
    636,
    637,
    638,
    639,
    640,
    641,
    642,
    643,
    644,
    645,
    646,
    647,
    648,
    649,
    650,
    651,
    652,
    653,
    654,
    655,
    656,
    657,
    658,
    659,
    660,
    661,
    662,
    663,
    664,
    665,
    666,
    667,
  ];

  static const List<int> _emojiS4 = <int>[
    763,
    764,
    765,
    766,
    767,
    768,
    769,
    770,
    771,
    772,
    773,
    774,
    775,
    776,
    777,
    778,
    779,
  ];

  static const List<int> _emojiS5 = <int>[
    43,
    44,
    45,
    46,
    47,
    49,
    50,
    51,
    52,
    53,
    54,
    55,
    56,
    57,
    58,
    59,
    60,
    61,
    63,
    64,
    65,
    66,
    67,
    68,
    69,
    70,
    72,
    73,
    74,
    75,
    77,
    78,
    79,
    80,
    82,
    83,
    84,
    85,
    86,
    91,
    92,
    93,
    94,
    95,
    96,
    97,
    98,
    99,
    100,
    101,
    102,
    103,
    104,
    105,
    106,
    107,
    108,
    109,
    110,
    111,
    112,
    113,
    114,
    115,
    116,
    117,
    118,
    119,
    286,
    287,
  ];

  // RiverSide `:emoji_name:` 与清水河畔可共用（Unicode 直出）的映射。
  // 通过本地抓取 RiverSide /emojis.json 并与清水河畔内置 Unicode 表情集合比对生成。
  static const Map<String, String> _riverToQingCommonEmoji = <String, String>{
    '+1': '👍',
    '-1': '👎',
    'backhand_index_pointing_down': '👇',
    'backhand_index_pointing_up': '👆',
    'clap': '👏',
    'downcast_face_with_sweat': '😓',
    'eyes': '👀',
    'face_blowing_a_kiss': '😘',
    'face_savoring_food': '😋',
    'face_vomiting': '🤮',
    'face_with_raised_eyebrow': '🤨',
    'face_with_steam_from_nose': '😤',
    'face_without_mouth': '😶',
    'flexed_biceps': '💪',
    'folded_hands': '🙏',
    'heart_eyes': '😍',
    'joy': '😂',
    'man': '👨',
    'ok_hand': '👌',
    'oncoming_fist': '👊',
    'partying_face': '🥳',
    'raised_fist': '✊',
    'raised_hand': '✋',
    'smiling_face_with_sunglasses': '😎',
    'smiling_face_with_three_hearts': '🥰',
    'smirking_face': '😏',
    'sob': '😭',
    'star_struck': '🤩',
    'sunglasses': '😎',
    'sweat_smile': '😅',
    'thinking': '🤔',
    'unamused_face': '😒',
    'waving_hand': '👋',
    'wink': '😉',
    'woman': '👩',
    'zany_face': '🤪',
  };

  static final RegExp _colonEmojiReg = RegExp(r':([a-zA-Z0-9_+\-]+):');
  static final RegExp _qingBracketTokenReg = RegExp(
    r'\[([as])\s*:\s*(\d+)\]',
    caseSensitive: false,
  );
  static final RegExp _qingColonTokenReg = RegExp(
    r':([as])_(\d+):',
    caseSensitive: false,
  );
  static final RegExp _riverNumericEmojiReg = RegExp(
    r'^([as])_?(\d+)$',
    caseSensitive: false,
  );

  static final Set<String> _qingEmojiKeys = (() {
    final keys = <String>{};
    for (final id in _emojiA) {
      keys.add('a_$id');
    }
    for (final id in _emojiS2) {
      keys.add('s_$id');
    }
    for (final id in _emojiS3) {
      keys.add('s_$id');
    }
    for (final id in _emojiS4) {
      keys.add('s_$id');
    }
    for (final id in _emojiS5) {
      keys.add('s_$id');
    }
    return keys;
  })();

  static bool isQingEmojiKey(String key) =>
      RegExp(r'^[as]_\d+$', caseSensitive: false).hasMatch(key.trim());

  static String? _mapRiverEmojiNameToQingKey(String name) {
    final key = name.trim().toLowerCase();
    if (key.isEmpty) {
      return null;
    }
    if (isQingEmojiKey(key) && _qingEmojiKeys.contains(key)) {
      return key;
    }
    final match = _riverNumericEmojiReg.firstMatch(key);
    if (match == null) {
      return null;
    }
    final prefix = (match.group(1) ?? '').toLowerCase();
    final id = (match.group(2) ?? '').trim();
    if ((prefix != 'a' && prefix != 's') || id.isEmpty) {
      return null;
    }
    final qingKey = '${prefix}_$id';
    if (_qingEmojiKeys.contains(qingKey)) {
      return qingKey;
    }
    return null;
  }

  static bool canMapRiverEmojiName(String name) {
    final key = name.trim().toLowerCase();
    if (key.isEmpty) {
      return false;
    }
    if (_riverToQingCommonEmoji.containsKey(key)) {
      return true;
    }
    return _mapRiverEmojiNameToQingKey(key) != null;
  }

  static Map<String, String> buildDualComposeEmojiUrlMap({
    required Map<String, String> riverEmojiUrls,
  }) {
    if (riverEmojiUrls.isEmpty) {
      return const <String, String>{};
    }
    final result = <String, String>{};
    for (final entry in riverEmojiUrls.entries) {
      final key = entry.key.trim();
      if (key.isEmpty) {
        continue;
      }
      if (!canMapRiverEmojiName(key)) {
        continue;
      }
      final url = entry.value.trim();
      if (url.isEmpty) {
        continue;
      }
      result[key] = url;
    }
    return result;
  }

  static Map<String, List<String>> buildDualComposeEmojiGroups({
    required Map<String, List<String>> riverEmojiGroups,
    required Map<String, String> dualEmojiUrls,
  }) {
    if (riverEmojiGroups.isEmpty || dualEmojiUrls.isEmpty) {
      return const <String, List<String>>{};
    }
    final available = dualEmojiUrls.keys
        .map((it) => it.trim().toLowerCase())
        .toSet();
    final result = <String, List<String>>{};
    riverEmojiGroups.forEach((groupName, names) {
      final filtered = <String>[];
      for (final rawName in names) {
        final name = rawName.trim();
        if (name.isEmpty) {
          continue;
        }
        if (available.contains(name.toLowerCase())) {
          filtered.add(name);
        }
      }
      if (filtered.isNotEmpty) {
        result[groupName] = filtered;
      }
    });
    return result;
  }

  // 将 RiverSide `:emoji_name:` 转换为清水河畔可识别的共同表情（Unicode）。
  // dual-post 场景下，无法映射的 RiverSide 自定义表情会被移除，只保留共同部分。
  static String convertRiverEmojiTokensToQingCommon(
    String source, {
    bool dropUnsupported = true,
  }) {
    var result = source.replaceAllMapped(_colonEmojiReg, (match) {
      final token = (match.group(0) ?? '');
      final key = (match.group(1) ?? '').trim();
      if (key.isEmpty) {
        return token;
      }
      if (isQingEmojiKey(key)) {
        return token;
      }
      final mapped = _riverToQingCommonEmoji[key.toLowerCase()];
      if (mapped != null && mapped.isNotEmpty) {
        return mapped;
      }
      final qingKey = _mapRiverEmojiNameToQingKey(key);
      if (qingKey != null && qingKey.isNotEmpty) {
        return ':$qingKey:';
      }
      return dropUnsupported ? '' : token;
    });
    if (dropUnsupported) {
      result = _normalizeAfterEmojiDrop(result);
    }
    return result;
  }

  // RiverSide 发帖时移除清水河畔专属的 `[a:xxx] / [s:xxx] / :a_xxx: / :s_xxx:`
  // 避免双发时把清水河畔私有 token 原样发到 RiverSide。
  static String stripQingOnlyEmojiTokensForRiver(String source) {
    var result = source.replaceAll(_qingBracketTokenReg, '');
    result = result.replaceAll(_qingColonTokenReg, '');
    return _normalizeAfterEmojiDrop(result);
  }

  static String _normalizeAfterEmojiDrop(String source) {
    var result = source
        .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
    return result;
  }

  static String keyFromTokenParts(String prefix, String id) =>
      '${prefix.toLowerCase()}_$id';

  static String tokenFromKey(String key) {
    final match = RegExp(
      r'^([as])_(\d+)$',
      caseSensitive: false,
    ).firstMatch(key.trim());
    if (match == null) {
      return ':$key:';
    }
    final prefix = (match.group(1) ?? '').toLowerCase();
    final id = match.group(2) ?? '';
    if (prefix.isEmpty || id.isEmpty) {
      return ':$key:';
    }
    return '[$prefix:$id]';
  }

  static String replaceBracketTagsWithColonKey(String source) {
    var result = source.replaceAllMapped(
      RegExp(r'\[([as])\s*:\s*(\d+)\]', caseSensitive: false),
      (match) {
        final prefix = (match.group(1) ?? '').toLowerCase();
        final id = (match.group(2) ?? '').trim();
        if ((prefix != 'a' && prefix != 's') || id.isEmpty) {
          return match.group(0) ?? '';
        }
        return ':${keyFromTokenParts(prefix, id)}:';
      },
    );
    // 兼容清水河畔部分接口直接返回 `:s100:` / `:a1135:` 形式。
    result = result.replaceAllMapped(
      RegExp(r':([as])(\d+):', caseSensitive: false),
      (match) {
        final prefix = (match.group(1) ?? '').toLowerCase();
        final id = (match.group(2) ?? '').trim();
        if ((prefix != 'a' && prefix != 's') || id.isEmpty) {
          return match.group(0) ?? '';
        }
        return ':${keyFromTokenParts(prefix, id)}:';
      },
    );
    return result;
  }

  static String normalizeForSubmit(String source) {
    return source.replaceAllMapped(
      RegExp(r':([as])_(\d+):', caseSensitive: false),
      (match) {
        final prefix = (match.group(1) ?? '').toLowerCase();
        final id = (match.group(2) ?? '').trim();
        if ((prefix != 'a' && prefix != 's') || id.isEmpty) {
          return match.group(0) ?? '';
        }
        return '[$prefix:$id]';
      },
    );
  }

  static Map<String, String> buildEmojiUrlMap() {
    final map = <String, String>{};
    _appendGroup(
      map: map,
      ids: _emojiA,
      keyPrefix: 'a',
      folder: '1',
      filePrefix: 'a',
    );
    _appendGroup(
      map: map,
      ids: _emojiS2,
      keyPrefix: 's',
      folder: '2',
      filePrefix: 's',
    );
    _appendGroup(
      map: map,
      ids: _emojiS3,
      keyPrefix: 's',
      folder: '3',
      filePrefix: 's',
    );
    _appendGroup(
      map: map,
      ids: _emojiS4,
      keyPrefix: 's',
      folder: '4',
      filePrefix: 's',
    );
    _appendGroup(
      map: map,
      ids: _emojiS5,
      keyPrefix: 's',
      folder: '5',
      filePrefix: 's',
    );
    return map;
  }

  static Map<String, List<String>> buildEmojiGroups() {
    return <String, List<String>>{
      '阿鲁': _emojiA.map((id) => 'a_$id').toList(growable: false),
      '兔斯基': _emojiS2.map((id) => 's_$id').toList(growable: false),
      '黄豆': _emojiS3.map((id) => 's_$id').toList(growable: false),
      '贱驴': _emojiS4.map((id) => 's_$id').toList(growable: false),
      '洋葱头': _emojiS5.map((id) => 's_$id').toList(growable: false),
    };
  }

  static void _appendGroup({
    required Map<String, String> map,
    required List<int> ids,
    required String keyPrefix,
    required String folder,
    required String filePrefix,
  }) {
    for (final id in ids) {
      final key = '${keyPrefix}_$id';
      map[key] = '$_assetPrefix/$folder/${filePrefix}_$id.gif';
    }
  }
}
