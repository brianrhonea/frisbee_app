import 'package:http/http.dart' as http;

import '../../domain/models/chat.dart';
import '../../domain/models/outbox.dart';
import 'api_client.dart';

/// What an upload is for (`UploadPurpose` in packages/shared/src/media.ts;
/// the app uses these three).
enum UploadPurpose {
  /// A photo on a player's post (`users/{uid}/posts/{postId}/...`).
  post,

  /// A photo on a team post (`teams/{teamId}/posts/{postId}/...`).
  teamImage,

  /// Any file in team chat or a direct message.
  chat,
}

/// Remembers which files of a queued item are already uploaded and ready,
/// so sending it again doesn't upload them again. Implemented by the offline
/// queue ([OutboxRepository]), which keeps them with the job on the device.
abstract interface class UploadLedger {
  /// The uploads of [jobId] that are ready, by the index of their file.
  Map<int, ReadyUpload> readyFor(String jobId);

  /// Notes that file [index] of [jobId] is uploaded and ready.
  Future<void> markReady(String jobId, int index, ReadyUpload upload);
}

/// A ledger that forgets when the app closes: for tests and anywhere
/// there's no queue.
class MemoryUploadLedger implements UploadLedger {
  final _ready = <String, Map<int, ReadyUpload>>{};

  @override
  Map<int, ReadyUpload> readyFor(String jobId) =>
      Map.of(_ready[jobId] ?? const {});

  @override
  Future<void> markReady(String jobId, int index, ReadyUpload upload) async {
    (_ready[jobId] ??= {})[index] = upload;
  }
}

/// Uploads files through the API (`/v1/uploads`), the way the website does
/// (apps/web/lib/upload.ts): asks for a signed URL, PUTs the file there,
/// then has the API check and compress it. The message, post or team post
/// then names the ready uploads in its `uploadIds`.
class UploadClient {
  UploadClient({required ApiClient? api, http.Client? client})
    : _api = api,
      _http = client ?? http.Client();

  final ApiClient? _api;
  final http.Client _http;

  /// Putting a file to Storage and the API checking it can take a while on
  /// a slow connection.
  static const _putTimeout = Duration(minutes: 2);

  /// The API compresses a photo inside the request.
  static const _completeTimeout = Duration(seconds: 90);

  /// Uploads [files] and returns the ready uploads, in order.
  ///
  /// [itemId] is the post, team post or message they belong to (the queue's
  /// job id), [targetId] the team (`teamImage`) or chat (`chat`:
  /// `teams/{t}/chats/{r}` or `conversations/{c}`). With a [ledger] (and
  /// [ledgerKey], the job id), a file that's already ready isn't uploaded
  /// again and each new one is noted as soon as it's ready, so a retry
  /// after a failure carries on where it stopped.
  Future<List<ReadyUpload>> uploadAll({
    required UploadPurpose purpose,
    required String itemId,
    String? targetId,
    required List<NewAttachment> files,
    UploadLedger? ledger,
    String? ledgerKey,
  }) async {
    final api = _api ?? (throw _noApi);
    final done = ledger != null && ledgerKey != null
        ? ledger.readyFor(ledgerKey)
        : const <int, ReadyUpload>{};
    final out = <ReadyUpload>[];
    for (final (i, file) in files.indexed) {
      final kept = done[i];
      if (kept != null && kept.name == file.name && kept.size == file.size) {
        out.add(kept);
        continue;
      }
      final upload = await _uploadOne(
        api,
        purpose: purpose,
        itemId: itemId,
        targetId: targetId,
        file: file,
      );
      if (ledger != null && ledgerKey != null) {
        await ledger.markReady(ledgerKey, i, upload);
      }
      out.add(upload);
    }
    return out;
  }

  /// What the API accepts (packages/shared/src/media.ts).
  static const _imageTypes = {
    'image/jpeg',
    'image/png',
    'image/heic',
    'image/heif',
    'image/webp',
    'image/gif',
  };
  static const _videoTypes = {
    'video/mp4',
    'video/quicktime',
    'video/x-m4v',
    'video/x-matroska',
    'video/webm',
    'video/3gpp',
  };

  /// The type [file] is uploaded as. A chat takes any file: a photo or
  /// video type the API accepts, a document type, else
  /// `application/octet-stream` (a `.bmp`, say), as the website sends it.
  /// Posts and team posts take photos only: null for anything else.
  static String? contentTypeOf(UploadPurpose purpose, NewAttachment file) {
    final type = file.contentType;
    if (_imageTypes.contains(type)) return type;
    if (purpose != UploadPurpose.chat) return null;
    if (_videoTypes.contains(type)) return type;
    final document = !type.startsWith('image/') && !type.startsWith('video/');
    return document ? type : 'application/octet-stream';
  }

  Future<ReadyUpload> _uploadOne(
    ApiClient api, {
    required UploadPurpose purpose,
    required String itemId,
    required String? targetId,
    required NewAttachment file,
  }) async {
    final isChat = purpose == UploadPurpose.chat;
    final name = file.name.trim();
    final contentType = contentTypeOf(purpose, file);
    if (contentType == null) {
      throw ApiException(
        'invalid_argument',
        "${file.name} isn't a photo we can use. "
            'Try JPEG, PNG, HEIC, WebP or GIF.',
      );
    }
    final ticket = await api.post('/v1/uploads', {
      'purpose': purpose.name,
      'contentType': contentType,
      'size': file.size,
      'itemId': itemId,
      'targetId': ?targetId,
      // Chat keeps the file's own name (and its video limit follows it).
      if (isChat && name.isNotEmpty)
        'name': name.length > 120 ? name.substring(name.length - 120) : name,
    });
    final id = ticket['id'];
    final url = ticket['uploadUrl'];
    if (id is! String || url is! String) {
      throw const ApiException(
        'internal',
        'Something went wrong. Please try again.',
      );
    }
    final headers = {
      for (final e in ((ticket['headers'] as Map?) ?? const {}).entries)
        '${e.key}': '${e.value}',
    };
    final put = http.Request('PUT', Uri.parse(url))
      ..headers.addAll(headers)
      ..bodyBytes = file.bytes;
    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _http.send(put).timeout(_putTimeout),
      ).timeout(_putTimeout);
    } on Exception {
      throw _offline;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final s = response.statusCode;
      // A server problem is worth another try; a refusal (an expired
      // address, a file Storage won't take) is the user's to retry.
      throw ApiException(
        s >= 500 || s == 408 || s == 429 ? 'internal' : 'failed_precondition',
        "Couldn't upload ${isChat ? file.name : 'the photo'}. Try again.",
      );
    }
    final done = await api.send(
      'POST',
      '/v1/uploads/${Uri.encodeComponent(id)}/complete',
      null,
      _completeTimeout,
    );
    if (done['status'] != 'ready') {
      throw ApiException(
        'invalid_argument',
        isChat
            ? "${file.name} couldn't be used. Try another."
            : "That photo couldn't be used. Try another.",
      );
    }
    return ReadyUpload(
      id: id,
      name: file.name,
      contentType: contentType,
      size: file.size,
    );
  }

  static const _noApi = ApiException(
    'failed_precondition',
    "This version of the app can't upload files. Update the app.",
  );

  static const _offline = ApiException(
    'unavailable',
    "Couldn't reach the server. Check your connection and try again.",
  );
}
