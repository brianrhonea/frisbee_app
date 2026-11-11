import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';

import '../../../data/repositories/workout_recorder/workout_recorder.dart';
import '../../../data/services/location_service.dart';
import '../../../domain/models/workout.dart';
import '../../../routing/routes.dart';
import '../../../utils/result.dart';
import '../../core/ui/confirm_dialog.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/status_views.dart';
import '../../posts/widgets/post_composer.dart';
import '../../posts/widgets/post_widgets.dart' show workoutIcon;
import '../view_models/record_workout_viewmodel.dart';
import 'route_widgets.dart';

/// Records a run or ride: a live map of the route, the clock, distance and
/// pace, and start, pause and finish. Finishing opens the composer to share
/// it.
class RecordWorkoutScreen extends StatefulWidget {
  const RecordWorkoutScreen({super.key, required this.viewModel});

  final RecordWorkoutViewModel viewModel;

  @override
  State<RecordWorkoutScreen> createState() => _RecordWorkoutScreenState();
}

class _RecordWorkoutScreenState extends State<RecordWorkoutScreen> {
  RecordWorkoutViewModel get vm => widget.viewModel;
  final _map = MapController();

  /// Keep the map on the user until they pan it themselves.
  bool _follow = true;
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    vm.addListener(_onChange);
  }

  @override
  void dispose() {
    vm.removeListener(_onChange);
    _map.dispose();
    super.dispose();
  }

  void _onChange() {
    final here = vm.here;
    if (_follow && _mapReady && here != null) {
      _map.move(latLngOfPoint(here), _map.camera.zoom);
    }
  }

  Future<void> _finish() async {
    final ok = await confirmDialog(
      context,
      title: 'Finish ${vm.activity.label.toLowerCase()}?',
      message: 'You can share it next.',
      confirmLabel: 'Finish',
    );
    if (!ok || !mounted) return;
    final workout = vm.finish();
    if (workout == null) {
      showSnackBar(
        context,
        'Nothing was recorded. Move a little and try again.',
      );
      vm.discard();
      return;
    }
    await _share(workout);
  }

  Future<void> _share(Workout workout) async {
    final id = await showPostComposer(context, recorded: workout);
    if (id == null || !mounted) return;
    vm.posted();
    context.pushReplacement(Routes.post(id));
  }

  Future<void> _discard() async {
    final ok = await confirmDialog(
      context,
      title: 'Discard this ${vm.activity.label.toLowerCase()}?',
      message: 'The route and time are thrown away.',
      confirmLabel: 'Discard',
      destructive: true,
    );
    if (ok) vm.discard();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([vm, vm.prepare]),
    builder: (context, _) {
      final active =
          vm.state == RecorderState.recording ||
          vm.state == RecorderState.paused;
      return Scaffold(
        appBar: AppBar(
          title: Text(switch (vm.state) {
            RecorderState.recording => 'Recording',
            RecorderState.paused => 'Paused',
            RecorderState.finished => 'Finished',
            _ => 'Record',
          }),
          actions: [
            if (active || vm.state == RecorderState.finished)
              IconButton(
                tooltip: 'Discard',
                onPressed: _discard,
                icon: const Icon(Icons.delete_outline),
              ),
          ],
        ),
        body: _body(context),
      );
    },
  );

  Widget _body(BuildContext context) {
    if (vm.prepare.running && vm.state == RecorderState.idle) {
      return const LoadingView();
    }
    if (vm.prepare.result case Error(:final error)) {
      return ErrorView(error: error);
    }
    if (vm.blocked case final why?) {
      return EmptyView(
        icon: Icons.location_off_outlined,
        title: why == LocationAccess.serviceOff
            ? 'Location is off'
            : 'Location permission needed',
        message: why == LocationAccess.serviceOff
            ? 'Turn on location to map your route.'
            : 'Allow Stall 10 to use your location to map your route '
                  'and time each mile.',
        action: Wrap(
          spacing: 8,
          children: [
            FilledButton(
              onPressed: vm.openSettings,
              child: const Text('Open settings'),
            ),
            OutlinedButton(
              onPressed: vm.prepare.execute,
              child: const Text('Try again'),
            ),
          ],
        ),
      );
    }
    final theme = Theme.of(context);
    final here = vm.here;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: here == null
                    ? const Center(child: Text('Finding you…'))
                    : Listener(
                        // Panning the map stops it following the user.
                        onPointerMove: (_) {
                          if (_follow) setState(() => _follow = false);
                        },
                        child: _LiveMap(
                          controller: _map,
                          vm: vm,
                          onReady: () => _mapReady = true,
                        ),
                      ),
              ),
              if (vm.weakSignal || vm.gpsError != null)
                Positioned(
                  top: 12,
                  left: 12,
                  child: Chip(
                    avatar: const Icon(Icons.gps_not_fixed, size: 18),
                    label: Text(
                      vm.gpsError != null
                          ? 'GPS error'
                          : 'Waiting for a GPS signal…',
                    ),
                  ),
                ),
              if (!_follow && here != null)
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: FloatingActionButton.small(
                    heroTag: null,
                    tooltip: 'Center on me',
                    onPressed: () {
                      setState(() => _follow = true);
                      _onChange();
                    },
                    child: const Icon(Icons.my_location),
                  ),
                ),
            ],
          ),
        ),
        Material(
          elevation: 8,
          color: theme.colorScheme.surface,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (vm.canChangeActivity) ...[
                    _ActivityPicker(vm: vm),
                    const SizedBox(height: 12),
                  ],
                  _Stats(vm: vm),
                  const SizedBox(height: 16),
                  _Controls(
                    vm: vm,
                    onFinish: _finish,
                    onShare: () => _share(vm.result!),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LiveMap extends StatelessWidget {
  const _LiveMap({
    required this.controller,
    required this.vm,
    required this.onReady,
  });

  final MapController controller;
  final RecordWorkoutViewModel vm;
  final VoidCallback onReady;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final path = [for (final p in vm.path) latLngOfPoint(p)];
    final here = latLngOfPoint(vm.here!);
    return FlutterMap(
      mapController: controller,
      options: MapOptions(
        initialCenter: here,
        initialZoom: 17,
        onMapReady: onReady,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      ),
      children: [
        ...RouteMapLayers.tiles(),
        if (path.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: path,
                strokeWidth: 5,
                color: scheme.primary,
                borderStrokeWidth: 1.5,
                borderColor: Colors.white,
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            if (path.isNotEmpty)
              RouteMapLayers.dot(path.first, const Color(0xFF2E7D32), 'Start'),
            RouteMapLayers.dot(here, scheme.primary, 'You', size: 20),
          ],
        ),
        RouteMapLayers.attribution(),
      ],
    );
  }
}

class _ActivityPicker extends StatelessWidget {
  const _ActivityPicker({required this.vm});

  final RecordWorkoutViewModel vm;

  @override
  Widget build(BuildContext context) => SegmentedButton<WorkoutActivity>(
    showSelectedIcon: false,
    segments: [
      for (final a in WorkoutActivity.tracked)
        ButtonSegment(
          value: a,
          icon: Icon(workoutIcon(a)),
          label: Text(a.label),
        ),
    ],
    selected: {vm.activity},
    onSelectionChanged: (s) => vm.selectActivity(s.first),
  );
}

class _Stats extends StatelessWidget {
  const _Stats({required this.vm});

  final RecordWorkoutViewModel vm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    const tabular = [FontFeature.tabularFigures()];
    final speed = vm.activity.showsSpeed;
    Widget stat(String label, String value) => Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: tabular,
            ),
          ),
          Text(label, style: muted),
        ],
      ),
    );
    return Column(
      children: [
        Text(
          vm.timeLabel,
          style: theme.textTheme.displayMedium?.copyWith(
            fontWeight: FontWeight.w800,
            fontFeatures: tabular,
          ),
        ),
        Text('Time', style: muted),
        const SizedBox(height: 12),
        Row(
          children: [
            stat('Distance', vm.distanceLabel),
            stat(speed ? 'Avg speed' : 'Avg pace', vm.averageLabel),
            stat(speed ? 'Speed' : 'Pace', vm.currentLabel),
          ],
        ),
      ],
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.vm,
    required this.onFinish,
    required this.onShare,
  });

  final RecordWorkoutViewModel vm;
  final VoidCallback onFinish;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    const size = Size.fromHeight(52);
    return switch (vm.state) {
      RecorderState.idle || RecorderState.ready => FilledButton.icon(
        style: FilledButton.styleFrom(minimumSize: size),
        onPressed: vm.state == RecorderState.ready ? vm.start : null,
        icon: const Icon(Icons.play_arrow),
        label: const Text('Start'),
      ),
      RecorderState.recording => FilledButton.tonalIcon(
        style: FilledButton.styleFrom(minimumSize: size),
        onPressed: vm.pause,
        icon: const Icon(Icons.pause),
        label: const Text('Pause'),
      ),
      RecorderState.paused => Row(
        children: [
          Expanded(
            child: FilledButton.tonalIcon(
              style: FilledButton.styleFrom(minimumSize: size),
              onPressed: vm.resume,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Resume'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: size),
              onPressed: onFinish,
              icon: const Icon(Icons.flag),
              label: const Text('Finish'),
            ),
          ),
        ],
      ),
      RecorderState.finished => FilledButton.icon(
        style: FilledButton.styleFrom(minimumSize: size),
        onPressed: onShare,
        icon: const Icon(Icons.send),
        label: const Text('Share'),
      ),
    };
  }
}
