import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/store_links.dart';
import '../../core/themes/theme.dart';

/// App Store and Google Play download buttons.
class StoreBadges extends StatelessWidget {
  const StoreBadges({super.key, this.alignment = WrapAlignment.start});

  final WrapAlignment alignment;

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: alignment,
    spacing: 12,
    runSpacing: 12,
    children: const [
      _Badge(
        icon: Icons.apple,
        small: 'Download on the',
        big: 'App Store',
        url: StoreLinks.appStore,
      ),
      _Badge(
        icon: Icons.shop_rounded,
        small: 'Get it on',
        big: 'Google Play',
        url: StoreLinks.playStore,
      ),
    ],
  );
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.icon,
    required this.small,
    required this.big,
    required this.url,
  });

  final IconData icon;
  final String small;
  final String big;
  final String url;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Tooltip(
      message: StoreLinks.live ? '' : 'Coming soon',
      child: Material(
        color: c.ink,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: StoreLinks.live ? () => launchUrl(Uri.parse(url)) : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 18, 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: c.background, size: 28),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      StoreLinks.live ? small : 'Coming soon to',
                      style: TextStyle(color: c.background, fontSize: 11),
                    ),
                    Text(
                      big,
                      style: TextStyle(
                        color: c.background,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
