import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../domain/models/calendar.dart' show SubscribePlatform;
import '../../../domain/models/directions.dart';

SubscribePlatform _platform() => switch (defaultTargetPlatform) {
  TargetPlatform.iOS => SubscribePlatform.ios,
  TargetPlatform.macOS => SubscribePlatform.macos,
  TargetPlatform.android => SubscribePlatform.android,
  _ => SubscribePlatform.other,
};

/// "Directions": asks which maps app to use (Apple Maps on Apple devices,
/// Google Maps, Waze; [directionsOptions]) and opens it there. Each opens
/// in its app when installed, otherwise in the browser.
Future<void> showDirectionsSheet(
  BuildContext context, {
  String? place,
  (double, double)? point,
}) async {
  final options = directionsOptions(_platform(), place: place, point: point);
  final picked = await showModalBottomSheet<DirectionsOption>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              'Get directions with',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
          for (final o in options)
            ListTile(
              leading: Icon(switch (o.app) {
                MapsApp.apple => Icons.map_outlined,
                MapsApp.google => Icons.directions_outlined,
                MapsApp.waze => Icons.navigation_outlined,
              }),
              title: Text(o.label),
              onTap: () => Navigator.pop(sheet, o),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (picked == null) return;
  await launchUrl(picked.url, mode: LaunchMode.externalApplication);
}
