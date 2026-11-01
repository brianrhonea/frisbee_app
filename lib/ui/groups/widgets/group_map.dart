import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../domain/models/team.dart';

/// OpenStreetMap tiles. Their tile policy asks apps to identify themselves,
/// which flutter_map does with [_packageName] in the User-Agent.
const _tileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const _packageName = 'com.brianrhonea.frisbee_app';

/// Widget tests have no network; they turn tiles off so maps render
/// without trying to download them.
@visibleForTesting
bool debugDisableMapTiles = false;

LatLng latLngOf(GroupLocation l) => LatLng(l.latitude, l.longitude);

/// A map centred on [center] with a pin on [pin], if any. Read only
/// unless [onTap] is given.
class GroupMap extends StatelessWidget {
  const GroupMap({
    super.key,
    required this.center,
    this.pin,
    this.zoom = 15,
    this.onTap,
    this.controller,
  });

  final LatLng center;
  final LatLng? pin;
  final double zoom;
  final ValueChanged<LatLng>? onTap;
  final MapController? controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FlutterMap(
      mapController: controller,
      options: MapOptions(
        initialCenter: center,
        initialZoom: zoom,
        onTap: onTap == null ? null : (_, point) => onTap!(point),
        interactionOptions: InteractionOptions(
          // A read-only map in a scrolling page shouldn't steal scrolls.
          flags: onTap == null
              ? InteractiveFlag.none
              : InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      ),
      children: [
        if (!debugDisableMapTiles)
          TileLayer(urlTemplate: _tileUrl, userAgentPackageName: _packageName),
        if (pin != null)
          MarkerLayer(
            markers: [
              Marker(
                point: pin!,
                width: 40,
                height: 40,
                alignment: Alignment.topCenter,
                child: Icon(
                  Icons.location_on,
                  size: 40,
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ),
        // Small type so the attribution fits narrow cards; it can't wrap.
        DefaultTextStyle.merge(
          style: const TextStyle(fontSize: 10),
          child: const SimpleAttributionWidget(
            source: Text('OpenStreetMap contributors'),
          ),
        ),
      ],
    );
  }
}

/// The group's location on its home page: a small map, the address and a
/// button to open it in the device's maps app.
class GroupMapCard extends StatelessWidget {
  const GroupMapCard({super.key, required this.location});

  final GroupLocation location;

  Future<void> _openInMaps() => launchUrl(
    Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': '${location.latitude},${location.longitude}',
    }),
    mode: LaunchMode.externalApplication,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final point = latLngOf(location);
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 180,
            child: GroupMap(center: point, pin: point),
          ),
          ListTile(
            leading: const Icon(Icons.place_outlined),
            title: Text(
              location.address.isEmpty ? 'Where we play' : location.address,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
            trailing: TextButton.icon(
              onPressed: _openInMaps,
              icon: const Icon(Icons.directions_outlined),
              label: const Text('Directions'),
            ),
          ),
        ],
      ),
    );
  }
}
