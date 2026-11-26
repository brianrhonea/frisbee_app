import 'package:flutter/material.dart';

import '../themes/theme.dart';

const appName = 'Stall 10';

/// Matches `version:` in pubspec.yaml (checked by test/version_test.dart).
/// The log of versions is in docs/CHANGELOG.md.
const appVersion = '0.0.59';

/// The build number, the `+N` in pubspec.yaml (checked by
/// test/version_test.dart). `meta/flags.minBuild` is compared with this.
const appBuild = 59;

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
  const AppWordmark({super.key, this.size = 28, this.color, this.logo = true});

  final double size;
  final Color? color;

  /// Whether the disc logo comes before the name; off in the phone's top
  /// bar, which shows just "Stall 10", as the website does.
  final bool logo;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (logo) ...[AppLogo(size: size), SizedBox(width: size * 0.32)],
        // The condensed italic "STALL 10", as on the website.
        Flexible(
          child: Text(
            appName.toUpperCase(),
            semanticsLabel: appName,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.fade,
            style: TextStyle(
              fontFamily: scoreFont,
              fontWeight: FontWeight.w800,
              fontStyle: FontStyle.italic,
              fontSize: size * 0.95,
              height: 1,
              letterSpacing: 0.2,
              color: color ?? c.ink,
            ),
          ),
        ),
      ],
    );
  }
}
