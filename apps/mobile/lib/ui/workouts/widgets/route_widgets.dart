import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../domain/models/workout.dart';
import '../../../domain/models/workout_route.dart';
import '../../groups/widgets/group_map.dart';

/// Miles or kilometres, from the device's region.
/// Safe to call from `initState`: it doesn't depend on inherited widgets.
DistanceUnit distanceUnitOf(BuildContext context) => DistanceUnit.forCountry(
  WidgetsBinding.instance.platformDispatcher.locale.countryCode,
);

LatLng latLngOfPoint(RoutePoint p) => LatLng(p.lat, p.lng);

/// A recorded route on a map: the path, a green start and a red finish,
/// framed to fit. Read only unless [interactive].
class RouteMap extends StatelessWidget {
  const RouteMap({
    super.key,
    required this.path,
    this.interactive = false,
    this.current,
    this.controller,
  });

  final List<RoutePoint> path;
  final bool interactive;

  /// Where the user is now, while recording; replaces the finish pin.
  final RoutePoint? current;
  final MapController? controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final points = [for (final p in path) latLngOfPoint(p)];
    final here = current == null ? null : latLngOfPoint(current!);
    final frame = [...points, ?here];
    return FlutterMap(
      mapController: controller,
      options: MapOptions(
        initialCenter: frame.isEmpty ? const LatLng(0, 0) : frame.first,
        initialZoom: frame.isEmpty ? 2 : 16,
        initialCameraFit: frame.length < 2
            ? null
            : CameraFit.coordinates(
                coordinates: frame,
                padding: const EdgeInsets.all(28),
                maxZoom: 17,
              ),
        interactionOptions: InteractionOptions(
          // A read-only map in a scrolling feed shouldn't steal scrolls.
          flags: interactive
              ? InteractiveFlag.all & ~InteractiveFlag.rotate
              : InteractiveFlag.none,
        ),
      ),
      children: [
        ...osmTileLayers(),
        if (points.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: points,
                strokeWidth: 4,
                color: scheme.primary,
                borderStrokeWidth: 1.5,
                borderColor: Colors.white,
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            if (points.isNotEmpty)
              RouteMapLayers.dot(
                points.first,
                const Color(0xFF2E7D32),
                'Start',
              ),
            if (here != null)
              RouteMapLayers.dot(here, scheme.primary, 'You are here', size: 18)
            else if (points.length >= 2)
              RouteMapLayers.dot(
                points.last,
                const Color(0xFFC62828),
                'Finish',
              ),
          ],
        ),
        osmAttribution(),
      ],
    );
  }
}

/// Pieces shared by the route maps.
abstract final class RouteMapLayers {
  static List<Widget> tiles() => osmTileLayers();
  static Widget attribution() => osmAttribution();

  /// A round pin with a white ring.
  static Marker dot(LatLng at, Color color, String label, {double size = 14}) =>
      Marker(
        point: at,
        width: size,
        height: size,
        child: Semantics(
          label: label,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: const [
                BoxShadow(blurRadius: 3, color: Color(0x55000000)),
              ],
            ),
          ),
        ),
      );
}

/// How long each mile (or kilometre) took, with a bar for how fast it was
/// next to the quickest. A switch flips between miles and kilometres.
class WorkoutSplits extends StatefulWidget {
  const WorkoutSplits({super.key, required this.workout});

  final Workout workout;

  @override
  State<WorkoutSplits> createState() => _WorkoutSplitsState();
}

class _WorkoutSplitsState extends State<WorkoutSplits> {
  DistanceUnit? _unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final unit = _unit ?? distanceUnitOf(context);
    final w = widget.workout;
    final route = w.route;
    final meters = w.meters;
    if (route == null || meters == null) return const SizedBox.shrink();
    final rows = splitRows(w, unit);
    if (rows.isEmpty) return const SizedBox.shrink();
    final fastest = rows.map((r) => r.secondsPerUnit).reduce(math.min);
    final speed = w.activity.showsSpeed;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('Splits', style: theme.textTheme.titleMedium),
            const Spacer(),
            SegmentedButton<DistanceUnit>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: const [
                ButtonSegment(value: DistanceUnit.mi, label: Text('mi')),
                ButtonSegment(value: DistanceUnit.km, label: Text('km')),
              ],
              selected: {unit},
              onSelectionChanged: (s) => setState(() => _unit = s.first),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            SizedBox(
              width: 56,
              child: Text(
                unit == DistanceUnit.mi ? 'Mile' : 'Km',
                style: muted,
              ),
            ),
            SizedBox(
              width: 84,
              child: Text(speed ? 'Speed' : 'Pace', style: muted),
            ),
            Expanded(child: Text('Time', style: muted)),
          ],
        ),
        const Divider(height: 12),
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                SizedBox(
                  width: 56,
                  child: Text(r.label, style: theme.textTheme.bodyMedium),
                ),
                SizedBox(
                  width: 84,
                  child: Text(
                    (speed
                            ? formatSpeed(r.seconds, r.meters, unit)
                            : formatPace(r.seconds, r.meters, unit)) ??
                        '–',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: (fastest / r.secondsPerUnit).clamp(
                            0.05,
                            1.0,
                          ),
                          child: Container(
                            height: 10,
                            decoration: BoxDecoration(
                              color: scheme.primary.withValues(alpha: 0.75),
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 56,
                        child: Text(
                          formatClock(Duration(seconds: r.seconds.round())),
                          textAlign: TextAlign.end,
                          style: muted?.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (route.elevationGainMeters case final g? when g >= 1) ...[
          const SizedBox(height: 8),
          Text(
            'Elevation gain '
            '${unit == DistanceUnit.mi ? '${(g * 3.28084).round()} ft' : '${g.round()} m'}',
            style: muted,
          ),
        ],
      ],
    );
  }
}

/// One row of [WorkoutSplits].
typedef SplitRow = ({
  String label,
  double seconds,
  double meters,
  double secondsPerUnit,
});

/// The whole miles (or km), then the part left over if it's big enough to
/// mean anything.
List<SplitRow> splitRows(Workout w, DistanceUnit unit) {
  final route = w.route;
  final total = w.meters;
  if (route == null || total == null) return const [];
  final splits = route.splits(unit);
  final rows = <SplitRow>[
    for (final (i, s) in splits.indexed)
      (
        label: '${i + 1}',
        seconds: s.toDouble(),
        meters: unit.meters,
        secondsPerUnit: s.toDouble(),
      ),
  ];
  final restMeters = total - splits.length * unit.meters;
  final restSeconds =
      w.duration.inSeconds - splits.fold<int>(0, (a, b) => a + b);
  if (restMeters >= unit.meters * 0.05 && restSeconds > 0) {
    rows.add((
      label: (restMeters / unit.meters).toStringAsFixed(2),
      seconds: restSeconds.toDouble(),
      meters: restMeters,
      secondsPerUnit: restSeconds * unit.meters / restMeters,
    ));
  }
  return rows;
}
