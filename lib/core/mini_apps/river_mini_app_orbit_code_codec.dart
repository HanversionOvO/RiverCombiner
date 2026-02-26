import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

class RiverMiniAppOrbitCode {
  const RiverMiniAppOrbitCode({
    required this.idHex,
    required this.checksumHex,
    required this.rotationDeg,
    required this.score,
  });

  final String idHex;
  final String checksumHex;
  final double rotationDeg;
  final double score;
}

/// refer_dart 风格实现：
/// - 统一归一化到 600x600
/// - 极坐标采样 36 射线/每射线 4 区段，跳过 3 条定位射线
/// - 提取 132bit（128bit id + 4bit checksum）
/// - 通过校验位确认有效性
///
/// 为兼容手机旋转拍摄，解码会在 0~358° 每 2° 尝试一次，并选择得分最高结果。
class RiverMiniAppOrbitCodeCodec {
  static const int _targetSize = 600;
  static const int _rayCount = 36;
  static const int _zonesPerRay = 4;
  static const Set<int> _locatorRays = <int>{0, 12, 24};

  static const double _baseRadius = 130;
  static const double _zoneWidth = 28;
  static const double _bitCenterOffset = 10;

  static RiverMiniAppOrbitCode? decodeFromImageBytes(Uint8List imageBytes) {
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null || decoded.width < 80 || decoded.height < 80) {
      return null;
    }
    return decodeFromImage(decoded);
  }

  static RiverMiniAppOrbitCode? decodeFromImage(img.Image image) {
    final candidates = decodeCandidatesFromImage(image);
    if (candidates.isEmpty) {
      return null;
    }
    return candidates.first;
  }

  static List<RiverMiniAppOrbitCode> decodeCandidatesFromImageBytes(
    Uint8List imageBytes, {
    int maxCandidates = 12,
  }) {
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null || decoded.width < 80 || decoded.height < 80) {
      return const <RiverMiniAppOrbitCode>[];
    }
    return decodeCandidatesFromImage(decoded, maxCandidates: maxCandidates);
  }

  static List<RiverMiniAppOrbitCode> decodeCandidatesFromImage(
    img.Image image, {
    int maxCandidates = 12,
  }) {
    final normalizedCandidates = _buildNormalizedCandidates(
      image,
      maxWindows: 12,
    );
    if (normalizedCandidates.isEmpty) {
      return const <RiverMiniAppOrbitCode>[];
    }

    const baseThresholds = <double>[236, 232, 228, 224];

    final dedup = <String, RiverMiniAppOrbitCode>{};
    for (final normalized in normalizedCandidates) {
      final thresholds = <double>[
        ...baseThresholds,
        _computeThreshold(normalized).clamp(210, 240),
      ];
      for (final threshold in thresholds) {
        for (var rotation = 0.0; rotation < 360.0; rotation += 2.0) {
          final candidate = _decodeAtRotation(
            image: normalized,
            threshold: threshold,
            rotationDeg: rotation,
          );
          if (candidate == null) {
            continue;
          }
          final key = '${candidate.idHex}:${candidate.checksumHex}';
          final current = dedup[key];
          if (current == null || candidate.score > current.score) {
            dedup[key] = candidate;
          }
        }
        final currentBest = dedup.values.isEmpty
            ? null
            : dedup.values.reduce((a, b) => a.score >= b.score ? a : b);
        if (currentBest != null && currentBest.score > 1.45) {
          break;
        }
      }
      final currentBest = dedup.values.isEmpty
          ? null
          : dedup.values.reduce((a, b) => a.score >= b.score ? a : b);
      if (currentBest != null && currentBest.score > 1.55) {
        break;
      }
    }
    final list = dedup.values.toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    if (list.length > maxCandidates) {
      return list.sublist(0, maxCandidates);
    }
    return list;
  }

  static List<img.Image> _buildNormalizedCandidates(
    img.Image source, {
    int maxWindows = 12,
  }) {
    final ranked = <_RankedImage>[];
    final seen = <String>{};

    void addCrop({required int left, required int top, required int side}) {
      if (side < 72) {
        return;
      }
      final maxLeft = source.width - side;
      final maxTop = source.height - side;
      if (maxLeft < 0 || maxTop < 0) {
        return;
      }
      final x = left.clamp(0, maxLeft).toInt();
      final y = top.clamp(0, maxTop).toInt();
      final key = '$x:$y:$side';
      if (!seen.add(key)) {
        return;
      }
      final crop = img.copyCrop(source, x: x, y: y, width: side, height: side);
      final normalized = _normalizeImage(crop);
      if (normalized.width == _targetSize && normalized.height == _targetSize) {
        final quick = _quickOrbitLikelihood(normalized);
        // 【修复】降低预检阈值，确保包含复杂 Logo 的码不被丢弃
        if (quick > 0.05) {
          ranked.add(_RankedImage(normalized, quick));
        }
      }
    }

    final minDim = math.min(source.width, source.height);
    if (minDim < 72) {
      return const <img.Image>[];
    }

    // Baseline: full-image center crop.
    addCrop(
      left: ((source.width - minDim) / 2).round(),
      top: ((source.height - minDim) / 2).round(),
      side: minDim,
    );

    // Screenshot/camera mode: multi-scale around center with slight offsets.
    final ratios = <double>[0.76, 0.66, 0.56, 0.48, 0.40, 0.34, 0.28, 0.22];
    final centers = <_Offset2>[
      const _Offset2(0.50, 0.50),
      const _Offset2(0.50, 0.44),
      const _Offset2(0.50, 0.56),
      const _Offset2(0.44, 0.50),
      const _Offset2(0.56, 0.50),
    ];

    for (final ratio in ratios) {
      final side = (minDim * ratio).round();
      if (side < 72) {
        continue;
      }
      for (final c in centers) {
        final cx = (source.width * c.x).round();
        final cy = (source.height * c.y).round();
        addCrop(left: cx - (side ~/ 2), top: cy - (side ~/ 2), side: side);
      }
    }

    if (ranked.isEmpty) {
      return const <img.Image>[];
    }
    ranked.sort((a, b) => b.score.compareTo(a.score));
    final output = <img.Image>[];
    final cap = math.max(1, maxWindows);
    for (var i = 0; i < ranked.length && i < cap; i++) {
      output.add(ranked[i].image);
    }
    return output;
  }

  static double _quickOrbitLikelihood(img.Image image) {
    const center = _Offset2(_targetSize / 2.0, _targetSize / 2.0);
    final threshold = _computeThreshold(image).clamp(210, 240).toDouble();

    final ringA = _sampleRingDarkRatio(
      image: image,
      center: center,
      radius: _targetSize * 0.31,
      threshold: threshold,
    );
    final ringB = _sampleRingDarkRatio(
      image: image,
      center: center,
      radius: _targetSize * 0.37,
      threshold: threshold,
    );
    final outer = _sampleRingDarkRatio(
      image: image,
      center: center,
      radius: _targetSize * 0.48,
      threshold: threshold,
    );

    // 【修复】去掉了 centerInner 的严厉惩罚，因为中心留给了品牌的 Logo 和文字，它本就可能是黑色的。
    final ring = (ringA + ringB) / 2.0;
    return ring - outer * 0.35;
  }

  static img.Image _normalizeImage(img.Image source) {
    final side = math.min(source.width, source.height);
    final left = ((source.width - side) / 2).round();
    final top = ((source.height - side) / 2).round();
    final square = img.copyCrop(
      source,
      x: left,
      y: top,
      width: side,
      height: side,
    );
    return img.copyResize(
      square,
      width: _targetSize,
      height: _targetSize,
      interpolation: img.Interpolation.average,
    );
  }

  static RiverMiniAppOrbitCode? _decodeAtRotation({
    required img.Image image,
    required double threshold,
    required double rotationDeg,
  }) {
    const center = _Offset2(_targetSize / 2.0, _targetSize / 2.0);

    final bits = <int>[];
    var certainty = 0.0;
    for (var ray = 0; ray < _rayCount; ray++) {
      if (_locatorRays.contains(ray)) {
        continue;
      }
      final angle = _rayAngleDeg(ray, rotationDeg);
      for (var z = 0; z < _zonesPerRay; z++) {
        final r = _baseRadius + z * _zoneWidth + _bitCenterOffset;
        final point = _pointAt(center, angle, r);
        final dark = _sampleCrossDarkRatio(
          image: image,
          center: point,
          threshold: threshold,
        );
        bits.add(dark >= 0.52 ? 1 : 0);
        certainty += (dark - 0.5).abs();
      }
    }
    if (bits.length != 132) {
      return null;
    }

    final ones = bits.where((v) => v == 1).length;
    final ratio = ones / bits.length;
    if (ratio < 0.12 || ratio > 0.88) {
      return null;
    }

    final idHex = _bitsToHex(bits, 0, 128).toLowerCase();
    final checksumHex = _bitsToHex(bits, 128, 4).toLowerCase();

    if (!_looksLikeValidOrbitId(idHex)) {
      return null;
    }

    final expected = _computeChecksumHex(idHex);
    if (checksumHex != expected) {
      return null;
    }

    final locatorLine = _locatorLineScore(
      image: image,
      center: center,
      threshold: threshold,
      rotationDeg: rotationDeg,
    );
    final locatorRing = _locatorRingScore(
      image: image,
      center: center,
      threshold: threshold,
      rotationDeg: rotationDeg,
    );

    // 【修复】去掉了冗余的 anchorScore，对称星环不需要该逻辑惩罚
    final score =
        certainty / bits.length + locatorLine * 0.75 + locatorRing * 0.58;

    if (locatorLine < 0.20 || locatorRing < 0.14) {
      return null;
    }

    return RiverMiniAppOrbitCode(
      idHex: idHex,
      checksumHex: checksumHex,
      rotationDeg: rotationDeg,
      score: score,
    );
  }

  static double _computeThreshold(img.Image image) {
    var sum = 0.0;
    var count = 0;
    final step = math.max(1, image.width ~/ 180);
    for (var y = 0; y < image.height; y += step) {
      for (var x = 0; x < image.width; x += step) {
        sum += _luma(image.getPixel(x, y));
        count++;
      }
    }
    if (count <= 0) {
      return 230;
    }
    return (sum / count) * 0.88;
  }

  static double _locatorLineScore({
    required img.Image image,
    required _Offset2 center,
    required double threshold,
    required double rotationDeg,
  }) {
    var total = 0.0;
    for (final ray in _locatorRays) {
      total += _sampleLineDarkRatio(
        image: image,
        center: center,
        angleDeg: _rayAngleDeg(ray, rotationDeg),
        fromRadius: _baseRadius,
        toRadius: _baseRadius + 3 * _zoneWidth,
        threshold: threshold,
      );
    }
    return total / _locatorRays.length;
  }

  static double _locatorRingScore({
    required img.Image image,
    required _Offset2 center,
    required double threshold,
    required double rotationDeg,
  }) {
    final circleCenterR = _baseRadius + 4.2 * _zoneWidth;
    // 【修复】对齐 React 画布中 "回" 字定位点的实际线条半径 12
    const ringRadius = 12.0;
    var total = 0.0;
    for (final ray in _locatorRays) {
      total += _sampleRingDarkRatio(
        image: image,
        center: _pointAt(center, _rayAngleDeg(ray, rotationDeg), circleCenterR),
        radius: ringRadius,
        threshold: threshold,
      );
    }
    return total / _locatorRays.length;
  }

  static double _sampleLineDarkRatio({
    required img.Image image,
    required _Offset2 center,
    required double angleDeg,
    required double fromRadius,
    required double toRadius,
    required double threshold,
  }) {
    const samples = 20;
    var dark = 0;
    for (var i = 0; i < samples; i++) {
      final t = (i + 0.5) / samples;
      final r = fromRadius + (toRadius - fromRadius) * t;
      final point = _pointAt(center, angleDeg, r);
      if (_isDark(image, point.x, point.y, threshold)) {
        dark++;
      }
    }
    return dark / samples;
  }

  static double _sampleRingDarkRatio({
    required img.Image image,
    required _Offset2 center,
    required double radius,
    required double threshold,
  }) {
    const samples = 24;
    var dark = 0;
    for (var i = 0; i < samples; i++) {
      final angle = i * (360.0 / samples);
      final point = _pointAt(center, angle, radius);
      if (_isDark(image, point.x, point.y, threshold)) {
        dark++;
      }
    }
    return dark / samples;
  }

  static double _sampleCrossDarkRatio({
    required img.Image image,
    required _Offset2 center,
    required double threshold,
  }) {
    const offsets = <_Offset2>[
      _Offset2(0, 0),
      _Offset2(-1.1, 0),
      _Offset2(1.1, 0),
      _Offset2(0, -1.1),
      _Offset2(0, 1.1),
      _Offset2(-0.8, -0.8),
      _Offset2(0.8, -0.8),
      _Offset2(-0.8, 0.8),
      _Offset2(0.8, 0.8),
    ];
    var dark = 0;
    for (final off in offsets) {
      if (_isDark(image, center.x + off.x, center.y + off.y, threshold)) {
        dark++;
      }
    }
    return dark / offsets.length;
  }

  static bool _isDark(img.Image image, double x, double y, double threshold) {
    final ix = x.round();
    final iy = y.round();
    if (ix < 0 || iy < 0 || ix >= image.width || iy >= image.height) {
      return false;
    }
    return _luma(image.getPixel(ix, iy)) <= threshold;
  }

  static String _bitsToHex(List<int> bits, int start, int bitCount) {
    final out = StringBuffer();
    final end = start + bitCount;
    for (var i = start; i < end; i += 4) {
      var nibble = 0;
      for (var b = 0; b < 4; b++) {
        nibble = (nibble << 1) | bits[i + b];
      }
      out.write(nibble.toRadixString(16));
    }
    return out.toString();
  }

  // 【最核心修复】匹配 React 端的按字节异或 (Byte XOR)，而不是半字节异或
  static String _computeChecksumHex(String idHex) {
    var acc = 0;
    // 每次截取 2 个 Hex 字符作为一个真实的 8 bit Byte 进行异或
    for (var i = 0; i < idHex.length; i += 2) {
      final hexByte = idHex.substring(i, i + 2);
      final byteValue = int.tryParse(hexByte, radix: 16) ?? 0;
      acc ^= byteValue;
    }
    // 最后和 React 一样取底层 4 bits 作为校验位
    return (acc & 0xF).toRadixString(16);
  }

  static bool _looksLikeValidOrbitId(String idHex) {
    final value = idHex.trim().toLowerCase();
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(value)) {
      return false;
    }
    if (value == '00000000000000000000000000000000') {
      return false;
    }
    final unique = value.split('').toSet().length;
    return unique >= 6;
  }

  static double _rayAngleDeg(int rayIndex, double rotationDeg) {
    return rayIndex * 10.0 + rotationDeg - 90.0;
  }

  static _Offset2 _pointAt(_Offset2 center, double angleDeg, double radius) {
    final angle = angleDeg * math.pi / 180.0;
    return _Offset2(
      center.x + math.cos(angle) * radius,
      center.y + math.sin(angle) * radius,
    );
  }

  static double _luma(img.Pixel pixel) {
    return pixel.r * 0.299 + pixel.g * 0.587 + pixel.b * 0.114;
  }
}

class _Offset2 {
  const _Offset2(this.x, this.y);
  final double x;
  final double y;
}

class _RankedImage {
  const _RankedImage(this.image, this.score);
  final img.Image image;
  final double score;
}
