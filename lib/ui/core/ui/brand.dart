import 'package:flutter/material.dart';

import '../themes/theme.dart';

const appName = 'UltiUP';

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

/// Logo followed by the app name.
class UltiUpWordmark extends StatelessWidget {
  const UltiUpWordmark({super.key, this.size = 28});

  final double size;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        UltiUpLogo(size: size),
        SizedBox(width: size * 0.3),
        Text(
          appName.toUpperCase(),
          style: TextStyle(
            fontFamily: headingFont,
            fontWeight: FontWeight.w700,
            fontStyle: FontStyle.italic,
            fontSize: size,
            height: 1,
            letterSpacing: 0.5,
            color: c.ink,
          ),
        ),
      ],
    );
  }
}
