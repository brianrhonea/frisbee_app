import 'package:flutter/material.dart';

import '../themes/theme.dart';

/// A person's photo, or their initials.
class PersonAvatar extends StatelessWidget {
  const PersonAvatar({
    super.key,
    required this.name,
    this.photoUrl,
    this.radius = 20,
  });

  final String name;
  final String? photoUrl;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final photo = photoUrl;
    final hasPhoto = photo != null && photo.isNotEmpty;
    final initials = name
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();
    return CircleAvatar(
      radius: radius,
      backgroundColor: c.feature,
      foregroundColor: c.onFeature,
      backgroundImage: hasPhoto ? NetworkImage(photo) : null,
      child: hasPhoto
          ? null
          : Text(
              initials.isEmpty ? '?' : initials,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: radius * 0.7,
              ),
            ),
    );
  }
}
