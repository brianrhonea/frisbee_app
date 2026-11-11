import 'dart:typed_data';

import '../../../data/repositories/browse/browse_repository.dart';
import '../../../domain/models/chat.dart';
import '../../../utils/result.dart';

/// Loads each public post photo once per page.
mixin PostImages {
  BrowseRepository get browse;

  final _images = <String, Future<Result<Uint8List>>>{};

  Future<Result<Uint8List>> loadImage(ChatAttachment image) =>
      _images[image.path] ??= browse.downloadImage(image);
}
