import 'package:flutter/material.dart';

import '../themes/theme.dart';

const appName = 'UltiUP';

/// Matches `version:` in pubspec.yaml (checked by test/version_test.dart).
/// The log of versions is in docs/CHANGELOG.md.
const appVersion = '0.0.8';

/// The app icon in use.
const logoAsset = 'assets/brand/ultiup_1b.png';

class UltiUpLogo extends StatelessWidget {
  const UltiUpLogo({super.key, this.size = 32, this.asset = logoAsset});

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
class UltiUpWordmark extends StatelessWidget {
  const UltiUpWordmark({super.key, this.size = 28, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        UltiUpLogo(size: size),
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
