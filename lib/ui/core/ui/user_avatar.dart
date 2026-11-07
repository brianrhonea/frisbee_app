import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/people/people_repository.dart';
import 'layout.dart' show PersonAvatar;

/// Someone's avatar with their current profile picture.
///
/// Posts, comments and messages save the author's photo when they're
/// written; this looks the person up in the people directory instead
/// (cached, see [PeopleRepository]), so a new picture shows everywhere.
/// [photoUrl] is shown until the lookup is back, or where there's no
/// directory (tests). The signed-in user's own photo comes straight from
/// their account, so it changes the moment they change it.
class UserAvatar extends StatefulWidget {
  const UserAvatar({
    super.key,
    required this.uid,
    required this.name,
    this.photoUrl,
    this.radius = 20,
  });

  final String uid;
  final String name;
  final String? photoUrl;
  final double radius;

  @override
  State<UserAvatar> createState() => _UserAvatarState();
}

class _UserAvatarState extends State<UserAvatar> {
  PeopleRepository? _people;
  AuthRepository? _auth;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final people = _maybe<PeopleRepository>();
    final auth = _maybe<AuthRepository>();
    if (people != _people) {
      _people?.removeListener(_changed);
      _people = people?..addListener(_changed);
      _lookUp();
    }
    if (auth != _auth) {
      _auth?.removeListener(_changed);
      _auth = auth?..addListener(_changed);
    }
  }

  T? _maybe<T>() {
    try {
      return Provider.of<T>(context, listen: false);
    } on ProviderNotFoundException {
      return null;
    }
  }

  @override
  void didUpdateWidget(UserAvatar old) {
    super.didUpdateWidget(old);
    if (old.uid != widget.uid) _lookUp();
  }

  /// After this frame: a lookup can answer (and notify) straight away.
  void _lookUp() {
    final people = _people;
    final uid = widget.uid;
    if (people == null || uid.isEmpty) return;
    scheduleMicrotask(() {
      if (mounted) unawaited(people.person(uid));
    });
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _people?.removeListener(_changed);
    _auth?.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final me = _auth?.currentUser;
    final String name;
    final String? photo;
    if (me != null && me.uid == widget.uid) {
      name = me.label;
      photo = me.photoUrl;
    } else if (_people?.cached(widget.uid) case final p?) {
      name = p.name.isEmpty ? widget.name : p.name;
      photo = p.photoUrl;
    } else {
      name = widget.name;
      photo = widget.photoUrl;
    }
    return PersonAvatar(name: name, photoUrl: photo, radius: widget.radius);
  }
}
