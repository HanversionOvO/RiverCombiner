import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Decode hidden payload embedded by miniapp_platform MiniAppCodeCard canvas.
///
/// Encoding contract (big-endian bits):
/// - sync: 16 bits (0xA5C3)
/// - payload length: 16 bits (bytes)
/// - payload bytes: UTF-8 text, prefixed with "RMC1|"
/// - crc: 8 bits, XOR of payload bytes
///
/// Bits are written into blue-channel LSB of pixels sampled on a 2px grid:
/// for y in [2, h-2), step 2; for x in [2, w-2), step 2.
class RiverMiniAppCodeImageCodec {
  static const int _syncWord = 0xA5C3;
  static const int _maxPayloadBytes = 4096;
  static const String _prefix = 'RMC1|';

  static String? decodeFromImageBytes(Uint8List imageBytes) {
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null || decoded.width < 16 || decoded.height < 16) {
      return null;
    }
    return decodeFromImage(decoded);
  }

  static String? decodeFromImage(img.Image image) {
    final direct = _decodeImageWithOffsets(image);
    if (direct != null) {
      return direct;
    }
    return _decodeFromCrops(image);
  }

  static String? _decodeImageWithOffsets(img.Image image) {
    const starts = <int>[2, 1, 0, 3];
    for (final sy in starts) {
      for (final sx in starts) {
        final decoded = _decodeBySampleGrid(
          image,
          startX: sx,
          startY: sy,
          step: 2,
        );
        if (decoded != null) {
          return decoded;
        }
      }
    }
    return null;
  }

  static String? _decodeFromCrops(img.Image image) {
    final pixelCount = image.width * image.height;
    final aspect = image.width >= image.height
        ? image.width / math.max(1, image.height)
        : image.height / math.max(1, image.width);
    // Hidden LSB payload is intended for original exported code images.
    // For large/long screenshots, exhaustive crop scan is expensive and
    // typically cannot recover payload after display/screenshot pipeline.
    if (pixelCount > 900000 || aspect > 1.8) {
      return null;
    }

    final minDim = math.min(image.width, image.height);
    if (minDim < 96) {
      return null;
    }

    const ratios = <double>[
      0.96,
      0.90,
      0.84,
      0.78,
      0.72,
      0.64,
      0.56,
      0.48,
      0.42,
      0.36,
      0.30,
      0.26,
      0.22,
      0.18,
    ];
    for (final ratio in ratios) {
      final side = (minDim * ratio).round();
      if (side < 64) {
        continue;
      }

      final xList = _anchors(image.width, side);
      final yList = _anchors(image.height, side);
      for (final top in yList) {
        for (final left in xList) {
          if (left < 0 ||
              top < 0 ||
              left + side > image.width ||
              top + side > image.height) {
            continue;
          }
          final cropped = img.copyCrop(
            image,
            x: left,
            y: top,
            width: side,
            height: side,
          );
          final decoded = _decodeImageWithOffsets(cropped);
          if (decoded != null) {
            return decoded;
          }
        }
      }
    }
    return null;
  }

  static List<int> _anchors(int full, int side) {
    final maxStart = full - side;
    if (maxStart <= 0) {
      return const <int>[0];
    }
    final set = <int>{
      0,
      maxStart,
      maxStart ~/ 2,
      maxStart ~/ 3,
      (maxStart * 2) ~/ 3,
      maxStart ~/ 4,
      (maxStart * 3) ~/ 4,
      maxStart ~/ 6,
      (maxStart * 5) ~/ 6,
    };
    final list = set.toList()..sort();
    return list;
  }

  static String? _decodeBySampleGrid(
    img.Image image, {
    required int startX,
    required int startY,
    required int step,
  }) {
    final bits = <int>[];
    final safeStep = step <= 0 ? 2 : step;
    final maxXExclusive = math.max(1, image.width - 2);
    final maxYExclusive = math.max(1, image.height - 2);
    final sx = startX.clamp(0, maxXExclusive - 1).toInt();
    final sy = startY.clamp(0, maxYExclusive - 1).toInt();
    for (var y = sy; y < maxYExclusive; y += safeStep) {
      for (var x = sx; x < maxXExclusive; x += safeStep) {
        final pixel = image.getPixel(x, y);
        bits.add(pixel.b.toInt() & 0x1);
      }
    }

    if (bits.length < 40) {
      return null;
    }

    final strict = _decodeStrict(bits);
    if (strict != null) {
      return strict;
    }
    final scanned = _decodeStrictBySyncScan(bits);
    if (scanned != null) {
      return scanned;
    }
    return _decodeFallback(bits);
  }

  static String? _decodeStrict(List<int> bits) {
    final sync = _readBits(bits, 0, 16);
    if (sync != _syncWord) {
      return null;
    }
    final payloadLen = _readBits(bits, 16, 16);
    if (payloadLen <= 0 || payloadLen > _maxPayloadBytes) {
      return null;
    }

    final totalBits = 16 + 16 + (payloadLen * 8) + 8;
    if (totalBits > bits.length) {
      return null;
    }

    final payload = Uint8List(payloadLen);
    var bitOffset = 32;
    for (var i = 0; i < payloadLen; i++) {
      payload[i] = _readBits(bits, bitOffset, 8);
      bitOffset += 8;
    }

    final crc = _readBits(bits, bitOffset, 8);
    var calc = 0;
    for (final b in payload) {
      calc ^= b;
    }
    if ((calc & 0xFF) != crc) {
      return null;
    }
    final extracted = _extractCode(payload);
    if (extracted == null) {
      return null;
    }
    if (!_looksLikeMiniAppCode(extracted)) {
      return null;
    }
    return extracted;
  }

  static String? _decodeStrictBySyncScan(List<int> bits) {
    if (bits.length < 40) {
      return null;
    }
    final limit = bits.length - 40;
    for (var offset = 0; offset <= limit; offset++) {
      final sync = _readBits(bits, offset, 16);
      if (sync != _syncWord) {
        continue;
      }
      final lenOffset = offset + 16;
      final payloadLen = _readBits(bits, lenOffset, 16);
      if (payloadLen <= 0 || payloadLen > _maxPayloadBytes) {
        continue;
      }
      final totalBits = 16 + 16 + (payloadLen * 8) + 8;
      if (offset + totalBits > bits.length) {
        continue;
      }
      final payload = Uint8List(payloadLen);
      var bitOffset = offset + 32;
      for (var i = 0; i < payloadLen; i++) {
        payload[i] = _readBits(bits, bitOffset, 8);
        bitOffset += 8;
      }
      final crc = _readBits(bits, bitOffset, 8);
      var calc = 0;
      for (final b in payload) {
        calc ^= b;
      }
      if ((calc & 0xFF) != crc) {
        continue;
      }
      final extracted = _extractCode(payload);
      if (extracted == null) {
        continue;
      }
      if (_looksLikeMiniAppCode(extracted)) {
        return extracted;
      }
    }
    return null;
  }

  static bool _looksLikeMiniAppCode(String code) {
    final value = code.trim();
    if (value.isEmpty) {
      return false;
    }
    if (value.startsWith('riverapp://miniapp/open') ||
        value.startsWith('river://miniapp/open')) {
      return true;
    }
    if (value.startsWith('{') && value.endsWith('}')) {
      return true;
    }
    return false;
  }

  static String? _decodeFallback(List<int> bits) {
    final marker = utf8.encode(_prefix);
    for (var shift = 0; shift < 8; shift++) {
      final bytes = _bitsToBytesWithShift(bits, shift);
      if (bytes.length < marker.length + 2) {
        continue;
      }
      final markerIndex = _indexOfBytes(bytes, marker);
      if (markerIndex < 0) {
        continue;
      }

      if (markerIndex >= 2) {
        final payloadLen =
            ((bytes[markerIndex - 2] << 8) | bytes[markerIndex - 1]) & 0xFFFF;
        if (payloadLen > 0 &&
            payloadLen <= _maxPayloadBytes &&
            markerIndex + payloadLen <= bytes.length) {
          final payload = Uint8List.fromList(
            bytes.sublist(markerIndex, markerIndex + payloadLen),
          );
          if (markerIndex + payloadLen < bytes.length) {
            final crc = bytes[markerIndex + payloadLen] & 0xFF;
            var calc = 0;
            for (final b in payload) {
              calc ^= b;
            }
            if ((calc & 0xFF) == crc) {
              final extracted = _extractCode(payload);
              if (extracted != null) {
                return extracted;
              }
            }
          }
          final extracted = _extractCode(payload);
          if (extracted != null) {
            return extracted;
          }
        }
      }

      final tail = Uint8List.fromList(bytes.sublist(markerIndex));
      final extracted = _extractCode(tail);
      if (extracted != null) {
        return extracted;
      }
    }
    return null;
  }

  static String? _extractCode(Uint8List payload) {
    if (payload.isEmpty) {
      return null;
    }
    final raw = utf8.decode(payload, allowMalformed: true);
    if (!raw.startsWith(_prefix)) {
      return null;
    }
    final code = raw.substring(_prefix.length).trim();
    return code.isEmpty ? null : code;
  }

  static List<int> _bitsToBytesWithShift(List<int> bits, int shift) {
    if (shift < 0 || shift > 7) {
      return const <int>[];
    }
    final available = bits.length - shift;
    final count = available ~/ 8;
    final out = List<int>.filled(count, 0, growable: false);
    var offset = shift;
    for (var i = 0; i < count; i++) {
      out[i] = _readBits(bits, offset, 8);
      offset += 8;
    }
    return out;
  }

  static int _indexOfBytes(List<int> source, List<int> pattern) {
    if (pattern.isEmpty || source.length < pattern.length) {
      return -1;
    }
    for (var i = 0; i <= source.length - pattern.length; i++) {
      var ok = true;
      for (var j = 0; j < pattern.length; j++) {
        if (source[i + j] != pattern[j]) {
          ok = false;
          break;
        }
      }
      if (ok) {
        return i;
      }
    }
    return -1;
  }

  static int _readBits(List<int> bits, int offset, int count) {
    var value = 0;
    for (var i = 0; i < count; i++) {
      value = (value << 1) | bits[offset + i];
    }
    return value;
  }
}
