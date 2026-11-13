import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Photos larger than this are read and shrunk before the
/// attachment size limit applies, so phone photos aren't turned away.
const maxPickedImageBytes = 50 * 1024 * 1024;

/// A picked photo after [ImageCompressor.shrink]: possibly renamed (a
/// `.png` re-encoded as JPEG becomes `.jpg`) and smaller.
typedef ShrunkImage = ({String name, Uint8List bytes});

/// Shrinks and re-encodes photos before upload to save storage and data.
///
/// Uses the pure-Dart `image` package, so it works on every platform
/// (Windows and web included), off the UI thread.
class ImageCompressor {
  const ImageCompressor({
    this.maxDimension = 1920,
    this.jpegQuality = 80,
    this.enabled = true,
  });

  /// The longest side, in pixels, after shrinking.
  final int maxDimension;
  final int jpegQuality;

  /// Off when the `compress_images` kill switch is off: photos upload as
  /// picked.
  final bool enabled;

  static const _skipped = {'gif', 'svg', 'heic', 'heif'};

  /// Returns a smaller copy of the image, or the original when it isn't a
  /// photo we handle, can't be decoded, or wouldn't get smaller.
  Future<ShrunkImage> shrink(String name, Uint8List bytes) async {
    final original = (name: name, bytes: bytes);
    if (!enabled || _skipped.contains(_extension(name))) return original;
    final args = (name, bytes, maxDimension, jpegQuality);
    final ShrunkImage? result;
    try {
      result = kIsWeb
          ? await compute(_shrink, args)
          : await Isolate.run(() => _shrink(args));
    } on Object {
      return original;
    }
    return result ?? original;
  }

  static String _extension(String name) {
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  }

  static ShrunkImage? _shrink((String, Uint8List, int, int) args) {
    final (name, bytes, maxDimension, quality) = args;
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    // Turn the photo upright, since re-encoding drops the EXIF orientation.
    var image = img.bakeOrientation(decoded);
    final longest = image.width > image.height ? image.width : image.height;
    if (longest > maxDimension) {
      image = image.width >= image.height
          ? img.copyResize(
              image,
              width: maxDimension,
              interpolation: img.Interpolation.average,
            )
          : img.copyResize(
              image,
              height: maxDimension,
              interpolation: img.Interpolation.average,
            );
    }
    final transparent = image.hasAlpha && _usesAlpha(image);
    final Uint8List out;
    final String outName;
    if (transparent) {
      out = img.encodePng(image, level: 9);
      outName = _withExtension(name, 'png');
    } else {
      out = img.encodeJpg(image, quality: quality);
      outName = _withExtension(name, 'jpg');
    }
    if (out.length >= bytes.length) return null;
    return (name: outName, bytes: out);
  }

  /// Whether any pixel is see-through; many PNGs carry an unused alpha
  /// channel and are better stored as JPEG.
  static bool _usesAlpha(img.Image image) {
    for (final p in image) {
      if (p.a < p.maxChannelValue) return true;
    }
    return false;
  }

  static String _withExtension(String name, String ext) {
    final dot = name.lastIndexOf('.');
    final base = dot < 0 ? name : name.substring(0, dot);
    return '$base.$ext';
  }
}
