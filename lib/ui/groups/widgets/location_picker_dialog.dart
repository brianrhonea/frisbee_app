import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../../domain/models/team.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/view_model_host.dart';
import '../view_models/location_picker_viewmodel.dart';
import 'group_map.dart';

/// Opens the location picker. Returns the chosen location, or null if
/// cancelled.
Future<GroupLocation?> pickGroupLocation(
  BuildContext context, {
  GroupLocation? initial,
}) => showDialog<GroupLocation>(
  context: context,
  builder: (_) => ViewModelHost(
    create: (c) =>
        LocationPickerViewModel(geocoding: c.read(), initial: initial),
    builder: (_, vm) => LocationPickerDialog(viewModel: vm),
  ),
);

/// Search an address, pick a match, then tap the map to fine-tune the pin.
class LocationPickerDialog extends StatefulWidget {
  const LocationPickerDialog({super.key, required this.viewModel});

  final LocationPickerViewModel viewModel;

  @override
  State<LocationPickerDialog> createState() => _LocationPickerDialogState();
}

class _LocationPickerDialogState extends State<LocationPickerDialog> {
  LocationPickerViewModel get vm => widget.viewModel;

  late final _query = TextEditingController(text: vm.picked?.address);
  final _map = MapController();
  bool _mapReady = false;

  /// Shown before anything is picked: the continental US.
  static const _defaultCenter = LatLng(39.5, -98.35);

  @override
  void initState() {
    super.initState();
    // The controller can only move the map once it has been laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) => _mapReady = true);
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _search() {
    final q = _query.text.trim();
    if (q.isNotEmpty) vm.search.execute(q);
  }

  void _pick(GroupLocation l) {
    vm.pick(l);
    if (_mapReady) _map.move(latLngOf(l), 15);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Where does the group play?'),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      content: SizedBox(
        width: 520,
        child: ListenableBuilder(
          listenable: Listenable.merge([vm, vm.search]),
          builder: (context, _) {
            final picked = vm.picked;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _query,
                  autofocus: picked == null,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _search(),
                  decoration: InputDecoration(
                    labelText: 'Search an address or park',
                    suffixIcon: vm.search.running
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : IconButton(
                            tooltip: 'Search',
                            icon: const Icon(Icons.search),
                            onPressed: _search,
                          ),
                  ),
                ),
                if (vm.search.error)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      errorMessage(vm.search.result),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (vm.noMatches)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('No places found. Try a fuller address.'),
                  ),
                if (vm.results.isNotEmpty)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 160),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final r in vm.results)
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.place_outlined),
                            title: Text(
                              r.address,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            selected: r == picked,
                            onTap: () => _pick(r),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    height: 240,
                    child: GroupMap(
                      controller: _map,
                      center: picked == null
                          ? _defaultCenter
                          : latLngOf(picked),
                      zoom: picked == null ? 3 : 15,
                      pin: picked == null ? null : latLngOf(picked),
                      onTap: (p) => vm.movePin(p.latitude, p.longitude),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Tap the map to move the pin.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ListenableBuilder(
          listenable: vm,
          builder: (context, _) => FilledButton(
            onPressed: vm.picked == null
                ? null
                : () => Navigator.pop(context, vm.picked),
            child: const Text('Use this place'),
          ),
        ),
      ],
    );
  }
}
