import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/services/image_compressor.dart';
import 'package:image/image.dart' as img;

/// A noisy photo-like image, so it doesn't compress to almost nothing.
img.Image _photo(int w, int h, {bool alpha = false}) {
  final image = img.Image(width: w, height: h, numChannels: alpha ? 4 : 3);
  final random = Random(1);
  for (final p in image) {
    // A smooth gradient with sensor-like noise.
    p
      ..r = (p.x * 255 ~/ w + random.nextInt(24)).clamp(0, 255)
      ..g = (p.y * 255 ~/ h + random.nextInt(24)).clamp(0, 255)
      ..b = (128 + random.nextInt(24)).clamp(0, 255);
    if (alpha) p.a = p.x < w / 2 ? 0 : 255;
  }
  return image;
}

void main() {
  const compressor = ImageCompressor();

  test('shrinks a big photo to 1920px and makes it smaller', () async {
    final original = img.encodePng(_photo(4000, 3000));
    final out = await compressor.shrink('IMG_1.png', original);
    expect(out.name, 'IMG_1.jpg');
    expect(out.bytes.length, lessThan(original.length));
    final decoded = img.decodeImage(out.bytes)!;
    expect(decoded.width, 1920);
    expect(decoded.height, 1440);
  });

  test('portrait photos are capped by height', () async {
    final original = img.encodeJpg(_photo(1000, 3000), quality: 100);
    final out = await compressor.shrink('p.jpg', original);
    final decoded = img.decodeImage(out.bytes)!;
    expect(decoded.height, 1920);
    expect(decoded.width, 640);
  });

  test('see-through PNGs stay PNG', () async {
    final original = img.encodePng(_photo(3000, 2000, alpha: true), level: 0);
    final out = await compressor.shrink('logo.png', original);
    expect(out.name, 'logo.png');
    expect(img.decodePng(out.bytes)!.width, 1920);
  });

  test('keeps the original when it would not get smaller', () async {
    final tiny = img.encodeJpg(_photo(40, 30), quality: 30);
    final out = await compressor.shrink('t.jpg', tiny);
    expect(out.bytes, same(tiny));
    expect(out.name, 't.jpg');
  });

  test('leaves GIFs, undecodable files and disabled runs alone', () async {
    final gif = img.encodeGif(_photo(2500, 2500));
    expect((await compressor.shrink('a.gif', gif)).bytes, same(gif));
    final junk = Uint8List.fromList(List.filled(5000, 7));
    expect((await compressor.shrink('b.jpg', junk)).bytes, same(junk));
    final big = img.encodePng(_photo(3000, 2000));
    const off = ImageCompressor(enabled: false);
    expect((await off.shrink('c.png', big)).bytes, same(big));
  });
}
