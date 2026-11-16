import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/follow/follow_repository.dart';
import '../../../data/repositories/team_post/team_post_repository.dart';
import '../../../data/repositories/user_post/user_post_repository.dart';
import '../../../data/services/file_picker_service.dart';
import '../../../domain/models/chat.dart';
import '../../../domain/models/follow.dart';
import '../../../domain/models/team.dart';
import '../../../domain/models/team_post.dart';
import '../../../domain/models/user_post.dart';
import '../../../domain/models/workout.dart';
import '../../../domain/models/workout_route.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';
import '../../teams/view_models/team_home_viewmodel.dart' show pickPostImages;

/// One exercise of a [WorkoutDraft], as typed.
class ExerciseDraft {
  ExerciseDraft({
    this.name = '',
    this.sets = '',
    this.reps = '',
    this.weight = '',
  });

  String name, sets, reps, weight;

  bool get isBlank =>
      name.trim().isEmpty &&
      sets.trim().isEmpty &&
      reps.trim().isEmpty &&
      weight.trim().isEmpty;
}

/// A workout as typed in the inline composer: numbers stay text until it's
/// posted (the website's WorkoutDraft).
class WorkoutDraft {
  WorkoutActivity activity = WorkoutActivity.run;
  String minutes = '';
  String distance = '';
  int? effort;
  final exercises = <ExerciseDraft>[];
}

/// The inline composer on Home (the website's Composer): a draft that
/// lives here, not in the widget, so it survives the box being rebuilt
/// (switching tabs, cards appearing above it). Type and post; the tools
/// add photos, links or a workout to the same box. With [audiences], a
/// "To" chip posts to Everyone or to one of those teams: a team post has a
/// title, a place and (unless it's a private group) a Public switch, and
/// no workout or tournament tag.
class InlineComposerViewModel extends ChangeNotifier {
  InlineComposerViewModel({
    required AuthRepository authRepository,
    required UserPostRepository userPostRepository,
    required TeamPostRepository teamPostRepository,
    required FollowRepository followRepository,
    required FilePickerService filePicker,
    List<Team> Function()? audiences,
  }) : _auth = authRepository,
       _userPosts = userPostRepository,
       _teamPosts = teamPostRepository,
       _picker = filePicker,
       _audiences = audiences ?? (() => const []) {
    post = Command0<PostedTo>(_post)..addListener(notifyListeners);
    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      _followSub = followRepository.watchFollows(uid).listen((f) {
        _tournaments = [
          for (final x in f)
            if (x.type == FollowType.tournament) x.target,
        ];
        notifyListeners();
      }, onError: (Object _) {});
    }
  }

  final AuthRepository _auth;
  final UserPostRepository _userPosts;
  final TeamPostRepository _teamPosts;
  final FilePickerService _picker;
  final List<Team> Function() _audiences;
  StreamSubscription<List<Follow>>? _followSub;

  /// Posts the draft, then clears it. Its value says where it went.
  late final Command0<PostedTo> post;

  // Audience ---------------------------------------------------------------

  /// Teams the user may post on from here, by name.
  List<Team> get audiences =>
      [..._audiences()]..sort((a, b) => a.name.compareTo(b.name));

  String? _teamId;

  /// The team posted to; null for Everyone (or once the user can no longer
  /// post on the team picked).
  Team? get team => _teamId == null
      ? null
      : _audiences().where((t) => t.id == _teamId).firstOrNull;

  /// Changes who the post is for. A team post has no workout or tournament
  /// tag, so picking a team drops them.
  void pickAudience(Team? to) {
    if (to?.id == _teamId) return;
    _teamId = to?.id;
    if (to != null) {
      _workout = null;
      _tagKey = null;
      _tagName = null;
    }
    _touch();
  }

  /// Whether the Public switch shows: a team post, not a private group's
  /// (whose posts stay with members).
  bool get offersPublic => team != null && !team!.isPrivateGroup;

  // Text -------------------------------------------------------------------

  String _body = '';
  String get body => _body;
  void setBody(String v) {
    if (v == _body) return;
    _body = v;
    _touch();
  }

  /// Characters left before [UserPost.maxBody].
  int get charactersLeft => UserPost.maxBody - _body.length;

  String _title = '';
  String get title => _title;
  void setTitle(String v) => _set(() => _title = v);

  String _place = '';
  String get place => _place;
  void setPlace(String v) => _set(() => _place = v);

  bool _public = false;
  bool get isPublic => _public;
  void setPublic(bool v) => _set(() => _public = v);

  // Links ------------------------------------------------------------------

  final _links = <String>[];
  List<String> get links => List.unmodifiable(_links);
  bool get canAddLink => _links.length < UserPost.maxLinks;

  bool _linkOpen = false;

  /// Whether the "Add a link" field shows (the Link tool opens it).
  bool get linkOpen => _linkOpen;
  void openLink() => _set(() => _linkOpen = true);
  void closeLink() => _set(() {
    _linkOpen = false;
    _linkText = '';
    _linkError = null;
  });

  String _linkText = '';
  String get linkText => _linkText;
  void setLinkText(String v) {
    if (v == _linkText) return;
    _linkText = v;
    _linkError = null;
    _touch();
  }

  String? _linkError;
  String? get linkError => _linkError;

  /// Adds the typed link; false (with [linkError]) when it isn't one.
  bool addLink() {
    if (_linkText.trim().isEmpty) {
      _set(() => _linkOpen = false);
      return true;
    }
    final link = TeamPost.normalizeLink(_linkText);
    if (link == null) {
      _set(() => _linkError = 'Enter a web address, like example.com/video');
      return false;
    }
    if (!canAddLink) {
      _set(() => _linkError = 'Up to ${UserPost.maxLinks} links');
      return false;
    }
    _set(() {
      if (!_links.contains(link)) _links.add(link);
      _linkText = '';
      _linkError = null;
      _linkOpen = false;
    });
    return true;
  }

  void removeLink(String link) => _set(() => _links.remove(link));

  // Photos -----------------------------------------------------------------

  final _photos = <NewAttachment>[];

  /// Photos picked, uploaded when the post is.
  List<NewAttachment> get photos => List.unmodifiable(_photos);
  bool get canAddPhotos => !_picking && _photos.length < UserPost.maxImages;

  bool _picking = false;
  bool get picking => _picking;

  /// Whether the camera can take a photo here.
  bool get canUseCamera => _picker.canUseCamera;

  Object? _notice;

  /// A problem with the photos just picked (text or an error); cleared by
  /// the next change.
  Object? get notice => _notice;

  /// Picks photos (or takes one) and adds them, up to the limit.
  Future<void> addPhotos({bool camera = false}) async {
    if (!canAddPhotos) return;
    _set(() => _picking = true);
    final result = await pickPostImages(_picker, camera: camera);
    _picking = false;
    switch (result) {
      case Ok(:final value):
        final room = UserPost.maxImages - _photos.length;
        _photos.addAll(value.take(room));
        _notice = value.length > room
            ? 'Posts can have up to ${UserPost.maxImages} photos.'
            : null;
      case Error(:final error):
        _notice = error;
    }
    _clearFailure();
    notifyListeners();
  }

  void removePhoto(NewAttachment photo) => _set(() => _photos.remove(photo));

  // Workout ----------------------------------------------------------------

  WorkoutDraft? _workout;

  /// The workout being added, if any (never on a team post).
  WorkoutDraft? get workout => _workout;

  /// Whether the Workout tool shows: posts to Everyone only.
  bool get offersWorkout => team == null;

  /// Adds a blank workout, or removes the one there.
  void toggleWorkout() {
    if (!offersWorkout) return;
    _set(() => _workout = _workout == null ? WorkoutDraft() : null);
  }

  void setActivity(WorkoutActivity a) => _setWorkout((w) => w.activity = a);
  void setMinutes(String v) => _setWorkout((w) => w.minutes = v);
  void setDistance(String v) => _setWorkout((w) => w.distance = v);
  void setEffort(int? v) => _setWorkout((w) => w.effort = v);

  bool get canAddExercise =>
      (_workout?.exercises.length ?? 0) < Workout.maxExercises;
  void addExercise() {
    if (canAddExercise) _setWorkout((w) => w.exercises.add(ExerciseDraft()));
  }

  void removeExercise(ExerciseDraft e) =>
      _setWorkout((w) => w.exercises.remove(e));

  void updateExercise(
    ExerciseDraft e, {
    String? name,
    String? sets,
    String? reps,
    String? weight,
  }) => _setWorkout((_) {
    if (name != null) e.name = name;
    if (sets != null) e.sets = sets;
    if (reps != null) e.reps = reps;
    if (weight != null) e.weight = weight;
  });

  void _setWorkout(void Function(WorkoutDraft) fn) {
    final w = _workout;
    if (w != null) _set(() => fn(w));
  }

  /// Distances are typed in this unit (the user's country's).
  DistanceUnit unit = DistanceUnit.km;

  // Tournament tag ---------------------------------------------------------

  List<FollowTarget> _tournaments = const [];

  /// Tournaments the user follows, to tag the post with (Everyone only).
  List<FollowTarget> get tournaments => team == null ? _tournaments : const [];

  String? _tagKey;
  String? _tagName;
  String? get tagKey => _tagKey;

  void setTag(String? key) => _set(() {
    _tagKey = key;
    _tagName = _tournaments.where((t) => t.key == key).firstOrNull?.name;
  });

  // Posting ----------------------------------------------------------------

  /// Whether there's something to post: words, a photo or a workout (links
  /// alone aren't a post), and nothing still being picked.
  bool get canPost => !post.running && !_picking && _hasContent;

  Future<Result<PostedTo>> _post() async {
    final me = _auth.currentUser;
    if (me == null) return Result.error(Exception('Not signed in'));
    // A link typed but not added still counts.
    if (_linkText.trim().isNotEmpty && !addLink()) {
      return Result.error(Exception(_linkError));
    }
    if (!_hasContent) {
      return Result.error(Exception('Write something or add a photo'));
    }
    final to = team;
    final Result<void> saved;
    if (to != null) {
      final draft = PostDraft(
        post: TeamPost(
          id: '',
          title: _title.trim(),
          body: _body.trim(),
          location: _place.trim(),
          links: List.of(_links),
          isPublic: _public && !to.isPrivateGroup,
        ),
        newImages: List.of(_photos),
      );
      saved = await _teamPosts.savePost(to.id, draft, me);
    } else {
      final Workout? workout;
      switch (_workoutValue()) {
        case Ok(:final value):
          workout = value;
        case Error(:final error):
          return Result.error(error);
      }
      final draft = UserPostDraft(
        post: UserPost(
          id: '',
          body: _body.trim(),
          links: List.of(_links),
          workout: workout,
          tournamentKey: _tagKey,
          tournamentName: _tagKey == null ? null : _tagName,
        ),
        newImages: List.of(_photos),
      );
      saved = await _userPosts.savePost(draft, me);
    }
    switch (saved) {
      case Ok():
        _clear();
        return Result.ok(PostedTo(teamId: to?.id, teamName: to?.name));
      case Error(:final error):
        return Result.error(error);
    }
  }

  bool get _hasContent =>
      charactersLeft >= 0 &&
      (_body.trim().isNotEmpty || _photos.isNotEmpty || _workout != null);

  /// The workout to post, or what's wrong with it (the old sheet's checks).
  Result<Workout?> _workoutValue() {
    final w = _workout;
    if (w == null) return const Result.ok(null);
    final minutes = int.tryParse(w.minutes.trim());
    if (minutes == null || minutes < 1 || minutes > Workout.maxMinutes) {
      return Result.error(Exception('How long, in minutes'));
    }
    double? km;
    final d = w.distance.trim().replaceAll(',', '.');
    if (d.isNotEmpty) {
      final n = double.tryParse(d);
      if (n == null ||
          n <= 0 ||
          n * unit.meters > Workout.maxDistanceKm * 1000) {
        return Result.error(Exception('Enter a distance in ${unit.label}'));
      }
      km = n * unit.meters / 1000;
    }
    final exercises = <WorkoutExercise>[];
    for (final e in w.exercises) {
      if (e.isBlank) continue;
      if (e.name.trim().isEmpty) {
        return Result.error(Exception('Name each exercise'));
      }
      int? whole(String v, int max) {
        if (v.trim().isEmpty) return null;
        final n = int.tryParse(v.trim());
        return n == null || n < 1 || n > max ? -1 : n;
      }

      final sets = whole(e.sets, 100);
      final reps = whole(e.reps, 1000);
      if (sets == -1) return Result.error(Exception('Sets go from 1 to 100'));
      if (reps == -1) return Result.error(Exception('Reps go from 1 to 1,000'));
      exercises.add(
        WorkoutExercise(
          name: e.name.trim(),
          sets: sets,
          reps: reps,
          weight: e.weight.trim(),
        ),
      );
    }
    final workout = Workout(
      activity: w.activity,
      durationMinutes: minutes,
      distanceKm: km,
      effort: w.effort,
      exercises: exercises,
    );
    if (workout.problem case final p?) return Result.error(Exception(p));
    return Result.ok(workout);
  }

  /// Empties the draft (the audience stays, as on the website).
  void _clear() {
    _body = '';
    _title = '';
    _place = '';
    _public = false;
    _links.clear();
    _linkText = '';
    _linkError = null;
    _linkOpen = false;
    _photos.clear();
    _notice = null;
    _workout = null;
    _tagKey = null;
    _tagName = null;
    notifyListeners();
  }

  /// A change to the draft: clears the last failure and notice.
  void _set(VoidCallback fn) {
    fn();
    _touch();
  }

  void _touch() {
    _notice = null;
    _clearFailure();
    notifyListeners();
  }

  void _clearFailure() {
    if (post.error) post.clearResult();
  }

  @override
  void dispose() {
    _followSub?.cancel();
    post
      ..removeListener(notifyListeners)
      ..dispose();
    super.dispose();
  }
}

/// Where a post went: Everyone (no team) or a team's feed.
class PostedTo {
  const PostedTo({this.teamId, this.teamName});

  final String? teamId;
  final String? teamName;

  bool get isTeam => teamId != null;
}
