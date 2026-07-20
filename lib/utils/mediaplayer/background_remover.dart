import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

/// BackgroundRemover — Utilities to remove the background from a sticker image
/// so it composites cleanly over video (YouTube/IG-style shoppable stickers).
///
/// Uses a chroma-key style removal of a near-solid background color (e.g. green
/// screen, white backdrop). Works fully offline with the `image` package.
class BackgroundRemover {
  /// Removes a near-solid background from raw encoded image bytes (PNG/JPG).
  /// Pixels whose color is within [tolerance] of [target] (default white)
  /// become fully transparent. Returns transparent PNG bytes.
  static Uint8List removeColorFromBytes(
    Uint8List encodedBytes, {
    Color target = const Color(0xFFFFFFFF),
    int tolerance = 60,
  }) {
    final image = img.decodeImage(encodedBytes);
    if (image == null) return encodedBytes;

    final tr = (target.r * 255.0).round().clamp(0, 255);
    final tg = (target.g * 255.0).round().clamp(0, 255);
    final tb = (target.b * 255.0).round().clamp(0, 255);
    final threshold = tolerance * 3;

    for (final p in image) {
      final r = p.r.toInt();
      final g = p.g.toInt();
      final b = p.b.toInt();
      final dist = (r - tr).abs() + (g - tg).abs() + (b - tb).abs();
      if (dist <= threshold) {
        // Knock out the pixel (fully transparent).
        p.a = 0;
      }
    }

    final encoded = img.encodePng(image);
    return Uint8List.fromList(encoded);
  }

  /// Convenience wrapper that takes a Flutter [ui.Image] and returns transparent
  /// PNG bytes.
  static Future<Uint8List> removeColorFromUiImage(
    ui.Image image, {
    Color target = const Color(0xFFFFFFFF),
    int tolerance = 60,
  }) async {
    final byteData =
        await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) return Uint8List(0);
    return removeColorFromBytes(
      byteData.buffer.asUint8List(),
      target: target,
      tolerance: tolerance,
    );
  }

  /// Loads an asset/image file into bytes for processing.
  static Future<Uint8List?> loadImageBytes(String path) async {
    try {
      final data = await rootBundle.load(path);
      return data.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }
}