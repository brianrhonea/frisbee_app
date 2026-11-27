import 'dart:convert';

import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:frisbee_app/data/services/api_client.dart';
import 'package:frisbee_app/data/services/upload_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// One request the app sent: method, path (with its query) and the decoded
/// JSON body (null when it had none).
typedef Sent = ({String method, String path, Object? body});

/// What the fake server answers: a status and a JSON body.
typedef Reply = ({int status, Object? body});

/// A reply with [status] and [body].
Reply reply(Object? body, [int status = 200]) => (status: status, body: body);

/// An API error answer, as the server writes it.
Reply apiError(int status, String code, String message) => (
  status: status,
  body: {
    'error': {'code': code, 'message': message},
  },
);

/// A fake Stall 10 API: records every request and answers by
/// `"METHOD /path"` (the path without its query). Unknown routes answer
/// 200 `{}`. A route's answer may be a function of the request, or a list
/// (one answer per call, the last repeats).
///
/// Also answers the PUT to a signed upload address (`https://storage.test`)
/// and keeps the bytes in [puts].
class FakeApi {
  FakeApi({this.uid = 'u1'});

  final String uid;

  /// While true every request fails to connect, as with no network.
  bool offline = false;
  final sent = <Sent>[];
  final puts = <String>[];
  final routes = <String, Object>{};
  final _calls = <String, int>{};

  /// Answers every call to [route] (`"POST /v1/posts"`) with [r].
  void on(String route, Object r) => routes[route] = r;

  /// The requests sent to [route].
  List<Sent> to(String route) => [
    for (final s in sent)
      if ('${s.method} ${s.path.split('?').first}' == route) s,
  ];

  /// The body of the one request to [route].
  Map<String, Object?> bodyOf(String route) {
    final r = to(route);
    if (r.length != 1) {
      throw StateError('Expected one $route, saw ${r.length}: $sent');
    }
    return (r.single.body as Map).cast<String, Object?>();
  }

  /// The upload client over this fake (its PUTs reach [puts]).
  UploadClient uploadClient() =>
      UploadClient(api: client(), client: httpClient);

  /// Makes the API client, signed in as [uid].
  ApiClient client({void Function(Map<String, String>)? onIncomplete}) =>
      ApiClient(
        baseUrl: Uri.parse('https://api.test'),
        auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: uid)),
        client: httpClient,
      )..onAccountIncomplete = onIncomplete;

  late final MockClient httpClient = MockClient((req) async {
    if (offline) throw http.ClientException('no network');
    if (req.url.host == 'storage.test') {
      puts.add('${req.method} ${req.url.path} ${req.bodyBytes.length}');
      final r = _answer('PUT storage', req);
      return _response(r);
    }
    final body = req.body.isEmpty ? null : jsonDecode(req.body);
    sent.add((
      method: req.method,
      path: req.url.hasQuery
          ? '${req.url.path}?${req.url.query}'
          : req.url.path,
      body: body,
    ));
    return _response(_answer('${req.method} ${req.url.path}', req, body));
  });

  Reply _answer(String route, http.BaseRequest req, [Object? body]) {
    var r = routes[route];
    if (r is List) {
      final n = _calls[route] = (_calls[route] ?? 0) + 1;
      r = r[(n - 1).clamp(0, r.length - 1)];
    }
    if (r is Function) r = r(body);
    if (r is Reply) return r;
    return (status: 200, body: r ?? const {});
  }

  http.Response _response(Reply r) => http.Response(
    r.body == null ? '' : jsonEncode(r.body),
    r.status,
    headers: {'content-type': 'application/json'},
  );
}

/// Routes that make `/v1/uploads` work: each create answers a fresh id
/// (`up1`, `up2`...) and a signed address on `storage.test`; complete says
/// ready. Returns the ids handed out, in order.
List<String> uploadsWork(FakeApi api) {
  final ids = <String>[];
  api.on('POST /v1/uploads', (Object? _) {
    final id = 'up${ids.length + 1}';
    ids.add(id);
    return {
      'id': id,
      'uploadUrl': 'https://storage.test/put/$id',
      'headers': {'Content-Type': 'image/jpeg'},
      'expiresAt': '2030-01-01T00:00:00Z',
    };
  });
  for (var i = 1; i <= 12; i++) {
    api.on('POST /v1/uploads/up$i/complete', {'id': 'up$i', 'status': 'ready'});
  }
  return ids;
}
