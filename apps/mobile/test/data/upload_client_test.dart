import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/services/api_client.dart';
import 'package:frisbee_app/data/services/upload_client.dart';
import 'package:frisbee_app/domain/models/chat.dart';
import 'package:frisbee_app/domain/models/outbox.dart';

import '../testing/api_fakes.dart';

NewAttachment _file(String name, [int n = 4]) =>
    NewAttachment(name: name, bytes: Uint8List(n));

void main() {
  late FakeApi api;
  late UploadClient uploads;
  late MemoryUploadLedger ledger;

  setUp(() {
    api = FakeApi();
    uploadsWork(api);
    ledger = MemoryUploadLedger();
    uploads = UploadClient(api: api.client(), client: api.httpClient);
  });

  test('creates, PUTs to the signed address, then completes', () async {
    final r = await uploads.uploadAll(
      purpose: UploadPurpose.post,
      itemId: 'job1',
      files: [_file('a.jpg', 10)],
    );
    expect([for (final u in r) u.id], ['up1']);
    expect(api.bodyOf('POST /v1/uploads'), {
      'purpose': 'post',
      'contentType': 'image/jpeg',
      'size': 10,
      'itemId': 'job1',
    });
    expect(api.puts, ['PUT /put/up1 10']);
    expect(api.to('POST /v1/uploads/up1/complete'), hasLength(1));
  });

  test('chat sends the file name and the chat as target', () async {
    await uploads.uploadAll(
      purpose: UploadPurpose.chat,
      itemId: 'job1',
      targetId: 'conversations/c1',
      files: [_file('plan.pdf')],
    );
    final b = api.bodyOf('POST /v1/uploads');
    expect(b['purpose'], 'chat');
    expect(b['targetId'], 'conversations/c1');
    expect(b['name'], 'plan.pdf');
    expect(b['contentType'], 'application/pdf');
  });

  test('chat sends a type the API takes: .bmp and unknown as octet', () async {
    await uploads.uploadAll(
      purpose: UploadPurpose.chat,
      itemId: 'j',
      targetId: 'conversations/c1',
      files: [_file('a.bmp'), _file('notes.xyz'), _file('clip.mov')],
    );
    expect(
      [
        for (final s in api.to('POST /v1/uploads'))
          (s.body as Map)['contentType'],
      ],
      [
        'application/octet-stream',
        'application/octet-stream',
        'video/quicktime',
      ],
    );
  });

  test('a post takes photos only, with a clear message', () async {
    await expectLater(
      uploads.uploadAll(
        purpose: UploadPurpose.post,
        itemId: 'j',
        files: [_file('a.bmp')],
      ),
      throwsA(
        isA<ApiException>()
            .having((e) => e.code, 'code', 'invalid_argument')
            .having((e) => e.message, 'message', contains('a.bmp')),
      ),
    );
    expect(api.to('POST /v1/uploads'), isEmpty);
  });

  test('a replay skips files already ready (partial failure)', () async {
    // The second file's completion fails the first time.
    api.on('POST /v1/uploads/up2/complete', [
      apiError(500, 'internal', 'Boom'),
      {'id': 'up2', 'status': 'ready'},
    ]);
    final files = [_file('a.jpg'), _file('b.jpg')];
    Future<List<ReadyUpload>> go() => uploads.uploadAll(
      purpose: UploadPurpose.post,
      itemId: 'job1',
      files: files,
      ledger: ledger,
      ledgerKey: 'job1',
    );
    await expectLater(go(), throwsA(isA<ApiException>()));
    expect(ledger.readyFor('job1').keys, [0]);
    final r = await go();
    expect([for (final u in r) u.id], ['up1', 'up3']);
    // Three creates in all, not four: the first file wasn't uploaded again.
    expect(api.to('POST /v1/uploads'), hasLength(3));
  });

  test('a file that is not ready is refused', () async {
    api.on('POST /v1/uploads/up1/complete', {'id': 'up1', 'status': 'failed'});
    await expectLater(
      uploads.uploadAll(
        purpose: UploadPurpose.post,
        itemId: 'job1',
        files: [_file('a.jpg')],
      ),
      throwsA(
        isA<ApiException>().having((e) => e.code, 'code', 'invalid_argument'),
      ),
    );
  });

  test('a refused PUT is a failure; a server error is retryable', () async {
    api.on('PUT storage', reply('', 403));
    await expectLater(
      uploads.uploadAll(
        purpose: UploadPurpose.post,
        itemId: 'j',
        files: [_file('a.jpg')],
      ),
      throwsA(
        isA<ApiException>().having(
          (e) => e.code,
          'code',
          'failed_precondition',
        ),
      ),
    );
    api.on('PUT storage', reply('', 503));
    await expectLater(
      uploads.uploadAll(
        purpose: UploadPurpose.post,
        itemId: 'j',
        files: [_file('a.jpg')],
      ),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'internal')),
    );
  });

  test('no API in this build: a clear error, no direct fallback', () async {
    await expectLater(
      UploadClient(api: null).uploadAll(
        purpose: UploadPurpose.post,
        itemId: 'j',
        files: [_file('a.jpg')],
      ),
      throwsA(isA<ApiException>()),
    );
  });
}
