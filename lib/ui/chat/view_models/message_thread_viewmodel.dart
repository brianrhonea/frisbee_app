import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/services/file_picker_service.dart';
import '../../../domain/models/app_user.dart';
import '../../../domain/models/chat.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

/// A list of messages with a composer: shared by team chat rooms and
/// direct messages. Subclasses say where messages come from and go.
abstract class MessageThreadViewModel extends ChangeNotifier {
  MessageThreadViewModel({
    required AuthRepository authRepository,
    required FilePickerService filePicker,
  }) : _auth = authRepository,
       _picker = filePicker {
    send = Command1<void, String>(_send);
    pickFiles = Command1<void, bool>(_pickFiles);
    deleteMessage = Command1<void, ChatMessage>(removeMessage);
    saveAttachment = Command1<bool, ChatAttachment>(_saveAttachment);
  }

  static const pageSize = 50;

  final AuthRepository _auth;
  final FilePickerService _picker;
  StreamSubscription<List<ChatMessage>>? _messageSub;

  /// Sends the composer's text with the pending attachments.
  late final Command1<void, String> send;

  /// Adds files to the pending attachments; true picks photos only.
  late final Command1<void, bool> pickFiles;
  late final Command1<void, ChatMessage> deleteMessage;

  /// Downloads an attachment and asks where to save it. False if cancelled.
  late final Command1<bool, ChatAttachment> saveAttachment;

  List<ChatMessage>? _messages;
  int _limit = pageSize;
  Object? _messageError;
  final _drafts = <NewAttachment>[];
  final _downloads = <String, Future<Result<Uint8List>>>{};

  // Where messages come from and go.
  @protected
  Stream<List<ChatMessage>> watchMessages(int limit);
  @protected
  Future<Result<void>> postMessage(
    AppUser author,
    String text,
    List<NewAttachment> attachments,
  );
  @protected
  Future<Result<void>> removeMessage(ChatMessage message);
  @protected
  Future<Result<Uint8List>> download(ChatAttachment attachment);

  bool get canWrite;

  /// Whether messages can carry photos and files.
  bool get canAttach => true;

  /// Who may delete [m] besides its author.
  @protected
  bool get canModerate => false;

  /// Called whenever a new page of messages arrives.
  @protected
  void onMessages(List<ChatMessage> messages) {}

  String get uid => _auth.currentUser?.uid ?? '';
  List<ChatMessage> get messages => _messages ?? const [];
  bool get messagesLoaded => _messages != null;
  Object? get messageError => _messageError;

  /// More messages may be on the server than the [pageSize]s loaded.
  bool get hasMore => messages.length >= _limit;

  /// Pending attachments for the next message.
  List<NewAttachment> get drafts => List.unmodifiable(_drafts);

  bool isMine(ChatMessage m) => m.authorId == uid;

  bool canDelete(ChatMessage m) => isMine(m) || canModerate;

  /// Starts (or restarts) listening; call from the subclass constructor.
  @protected
  void startMessages() {
    _messageSub?.cancel();
    _messageSub = watchMessages(_limit).listen((m) {
      _messages = m;
      _messageError = null;
      onMessages(m);
      notifyListeners();
    }, onError: _onMessageError);
  }

  void _onMessageError(Object e) {
    _messageError = e;
    _messages ??= const [];
    notifyListeners();
  }

  void loadMore() {
    _limit += pageSize;
    startMessages();
  }

  void removeDraft(NewAttachment a) {
    _drafts.remove(a);
    notifyListeners();
  }

  /// Attachment bytes, fetched once per attachment.
  Future<Result<Uint8List>> attachmentData(ChatAttachment a) =>
      _downloads[a.path] ??= download(a).then((r) {
        if (r is Error) _downloads.remove(a.path);
        return r;
      });

  Future<Result<void>> _send(String text) async {
    final user = _auth.currentUser;
    if (user == null) return Result.error(Exception('Not signed in'));
    if (text.trim().isEmpty && _drafts.isEmpty) return const Result.ok(null);
    final attachments = List.of(_drafts);
    final result = await postMessage(user, text, attachments);
    if (result is Ok) {
      _drafts.removeWhere(attachments.contains);
      notifyListeners();
    }
    return result;
  }

  Future<Result<void>> _pickFiles(bool imagesOnly) async {
    final List<PickedFile> picked;
    try {
      picked = await _picker.pick(imagesOnly: imagesOnly);
    } on Exception catch (e) {
      return Result.error(e);
    }
    final tooLarge = <String>[];
    for (final f in picked) {
      if ((f.size ?? 0) > maxAttachmentBytes) {
        tooLarge.add(f.name);
        continue;
      }
      final a = NewAttachment(name: f.name, bytes: await f.read());
      if (a.tooLarge) {
        tooLarge.add(f.name);
      } else {
        _drafts.add(a);
      }
    }
    notifyListeners();
    if (tooLarge.isNotEmpty) {
      return Result.error(AttachmentTooLargeException(tooLarge.join(', ')));
    }
    return const Result.ok(null);
  }

  Future<Result<bool>> _saveAttachment(ChatAttachment a) async {
    final data = await attachmentData(a);
    switch (data) {
      case Error(:final error):
        return Result.error(error);
      case Ok(:final value):
        try {
          return Result.ok(await _picker.save(a.name, value, a.contentType));
        } on Exception catch (e) {
          return Result.error(e);
        }
    }
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    super.dispose();
  }
}
