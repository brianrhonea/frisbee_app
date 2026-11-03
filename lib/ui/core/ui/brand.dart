import 'package:flutter/material.dart';

import '../themes/theme.dart';

const appName = 'Stall 10';

/// Matches `version:` in pubspec.yaml (checked by test/version_test.dart).
/// The log of versions is in docs/CHANGELOG.md.
const appVersion = '0.0.10';

/// The app icon: a "10" whose "0" is a flying disc. Drawn, with every
/// platform's launcher icon, by tool/brand/stall10_logo.py.
const logoAsset = 'assets/brand/stall10_logo.png';

class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 32, this.asset = logoAsset});

  final double size;
  final String asset;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(size * 0.22),
    child: Image.asset(
      asset,
      width: size,
      height: size,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.medium,
      semanticLabel: appName,
    ),
  );
}

/// Logo followed by the app name, in [color] (default: the page's ink).
class AppWordmark extends StatelessWidget {
  const AppWordmark({super.key, this.size = 28, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppLogo(size: size),
        SizedBox(width: size * 0.32),
        Text(
          appName,
          style: TextStyle(
            fontFamily: appFont,
            fontWeight: FontWeight.w800,
            fontSize: size * 0.72,
            height: 1,
            letterSpacing: -0.6,
            color: color ?? c.ink,
          ),
        ),
      ],
    );
  }
}
