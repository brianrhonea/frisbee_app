import 'model_utils.dart';

/// Why something is reported, in the order the sheet lists them. The same
/// names and labels as `reportReasons` in packages/shared/src/moderation.ts
/// (test/ui/report_block_test.dart checks they match).
enum ReportReason {
  spam('Spam or scam'),
  harassment('Bullying or harassment'),
  hate('Hate speech or symbols'),
  sexual('Nudity or sexual content'),
  violence('Violence or threats'),
  selfHarm('Self-harm or suicide', wire: 'self_harm'),
  minorSafety('Puts a young player at risk', wire: 'minor_safety'),
  impersonation('Pretending to be someone else'),
  other('Something else');

  const ReportReason(this.label, {String? wire}) : _wire = wire;

  final String label;
  final String? _wire;

  /// The name the API uses.
  String get wire => _wire ?? name;

  static ReportReason fromWire(Object? v) =>
      values.firstWhere((r) => r.wire == v, orElse: () => ReportReason.other);
}

/// The most a report's details say (`reportDetailsMax`).
const reportDetailsMax = 1000;

/// What a report is about (`reportTargetSchema`). Team kinds also go to
/// that team's admins.
sealed class ReportTarget {
  const ReportTarget();

  /// What the sheet calls it: post, comment, message or profile.
  String get noun;

  /// Whether the team's admins see it too.
  bool get team => false;

  Map<String, Object?> toJson();

  static ReportTarget? fromJson(Object? json) {
    if (json is! Map) return null;
    String s(String k) => json[k] as String? ?? '';
    return switch (json['kind']) {
      'post' => PostReport(s('postId')),
      'comment' => CommentReport(s('postId'), s('commentId')),
      'teamPost' => TeamPostReport(s('teamId'), s('postId')),
      'teamPostComment' => TeamPostCommentReport(
        s('teamId'),
        s('postId'),
        s('commentId'),
      ),
      'teamMessage' => TeamMessageReport(
        s('teamId'),
        s('roomId'),
        s('messageId'),
      ),
      'directMessage' => DirectMessageReport(
        s('conversationId'),
        s('messageId'),
      ),
      'user' => PersonReport(s('uid')),
      _ => null,
    };
  }
}

class PostReport extends ReportTarget {
  const PostReport(this.postId);
  final String postId;
  @override
  String get noun => 'post';
  @override
  Map<String, Object?> toJson() => {'kind': 'post', 'postId': postId};
}

class CommentReport extends ReportTarget {
  const CommentReport(this.postId, this.commentId);
  final String postId;
  final String commentId;
  @override
  String get noun => 'comment';
  @override
  Map<String, Object?> toJson() => {
    'kind': 'comment',
    'postId': postId,
    'commentId': commentId,
  };
}

class TeamPostReport extends ReportTarget {
  const TeamPostReport(this.teamId, this.postId);
  final String teamId;
  final String postId;
  @override
  String get noun => 'post';
  @override
  bool get team => true;
  @override
  Map<String, Object?> toJson() => {
    'kind': 'teamPost',
    'teamId': teamId,
    'postId': postId,
  };
}

class TeamPostCommentReport extends ReportTarget {
  const TeamPostCommentReport(this.teamId, this.postId, this.commentId);
  final String teamId;
  final String postId;
  final String commentId;
  @override
  String get noun => 'comment';
  @override
  bool get team => true;
  @override
  Map<String, Object?> toJson() => {
    'kind': 'teamPostComment',
    'teamId': teamId,
    'postId': postId,
    'commentId': commentId,
  };
}

class TeamMessageReport extends ReportTarget {
  const TeamMessageReport(this.teamId, this.roomId, this.messageId);
  final String teamId;
  final String roomId;
  final String messageId;
  @override
  String get noun => 'message';
  @override
  bool get team => true;
  @override
  Map<String, Object?> toJson() => {
    'kind': 'teamMessage',
    'teamId': teamId,
    'roomId': roomId,
    'messageId': messageId,
  };
}

class DirectMessageReport extends ReportTarget {
  const DirectMessageReport(this.conversationId, this.messageId);
  final String conversationId;
  final String messageId;
  @override
  String get noun => 'message';
  @override
  Map<String, Object?> toJson() => {
    'kind': 'directMessage',
    'conversationId': conversationId,
    'messageId': messageId,
  };
}

class PersonReport extends ReportTarget {
  const PersonReport(this.uid);
  final String uid;
  @override
  String get noun => 'profile';
  @override
  Map<String, Object?> toJson() => {'kind': 'user', 'uid': uid};
}

/// A report in the team's Reports (`ReportInfo`; reporters stay anonymous there).
class ReportInfo {
  const ReportInfo({
    required this.id,
    required this.target,
    required this.reason,
    required this.authorId,
    required this.authorName,
    this.details,
    this.text = '',
    this.images = const [],
    this.teamName,
    this.createdAt,
  });

  final String id;
  final ReportTarget? target;
  final ReportReason reason;
  final String? details;
  final String authorId;
  final String authorName;

  /// What it said when it was reported.
  final String text;
  final List<String> images;
  final String? teamName;
  final DateTime? createdAt;

  factory ReportInfo.fromMap(Map<String, Object?> m) {
    final snap = m['snapshot'] is Map
        ? (m['snapshot'] as Map).cast<String, Object?>()
        : const <String, Object?>{};
    return ReportInfo(
      id: m['id'] as String? ?? '',
      target: ReportTarget.fromJson(m['target']),
      reason: ReportReason.fromWire(m['reason']),
      details: m['details'] as String?,
      authorId: m['authorId'] as String? ?? '',
      authorName: m['authorName'] as String? ?? '',
      text: snap['text'] as String? ?? '',
      images: [
        for (final u in (snap['images'] as List?) ?? const [])
          if (u is String) u,
      ],
      teamName: m['teamName'] as String?,
      createdAt: parseDate(m['createdAt']),
    );
  }
}

/// Someone the user blocked (`users/{uid}/blocks/{other}` with `mine`).
class BlockedAccount {
  const BlockedAccount({
    required this.uid,
    required this.name,
    this.username,
    this.photoUrl,
  });

  final String uid;
  final String name;
  final String? username;
  final String? photoUrl;
}

/// Every block record the user holds: who they blocked ([mine]) and
/// everyone hidden from them either way ([hidden]).
class BlockList {
  const BlockList({this.mine = const [], this.hidden = const {}});

  static const empty = BlockList();

  final List<BlockedAccount> mine;
  final Set<String> hidden;

  /// Whether [uid] is hidden from the user (either blocked the other).
  bool hides(String? uid) => uid != null && hidden.contains(uid);

  /// Whether the user blocked [uid] themselves (and can unblock).
  bool blockedByMe(String? uid) => uid != null && mine.any((b) => b.uid == uid);
}

/// What blocking does, as the confirm and Blocked accounts say it.
const blockExplainer =
    "You won't see each other's posts, comments or messages, and neither of "
    "you can follow or message the other. Teams you share still work. "
    "They aren't told.";
