import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/themes/theme.dart';
import '../../core/ui/brand.dart';

/// The site's static pages (hosting/), outside the Flutter app.
typedef SitePage = ({String label, String path});

const List<SitePage> sitePages = [
  (label: 'About', path: '/about'),
  (label: 'Help', path: '/help'),
  (label: 'Terms of Service', path: '/terms'),
  (label: 'Privacy Policy', path: '/privacy'),
  (label: 'Cookie Policy', path: '/cookies'),
];

/// Opens one of the site's static pages in this tab.
Future<void> openSitePage(String path) =>
    launchUrl(Uri.base.resolve(path), webOnlyWindowName: '_self');

/// The footer links under the right column, like x.com's: the static
/// pages and the copyright line.
class WebFooterLinks extends StatelessWidget {
  const WebFooterLinks({super.key, this.alignment = WrapAlignment.start});

  final WrapAlignment alignment;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final style = TextStyle(color: c.muted, fontSize: 12.5);
    return Wrap(
      alignment: alignment,
      spacing: 12,
      runSpacing: 6,
      children: [
        for (final page in sitePages)
          InkWell(
            onTap: () => openSitePage(page.path),
            child: Text(page.label, style: style),
          ),
        Text('© ${DateTime.now().year} $appName', style: style),
      ],
    );
  }
}
