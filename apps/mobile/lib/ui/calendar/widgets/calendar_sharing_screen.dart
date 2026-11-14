import 'dart:async';

import 'package:flutter/material.dart';

import '../../../domain/models/shared_calendar.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/layout.dart' show PersonAvatar;
import '../../settings/widgets/settings_widgets.dart';
import '../view_models/calendar_sharing_viewmodel.dart';

/// Settings → Calendar sharing: the people who see the user's personal
/// events in their schedule, and a search to add more.
class CalendarSharingScreen extends StatefulWidget {
  const CalendarSharingScreen({super.key, required this.viewModel});

  final CalendarSharingViewModel viewModel;

  @override
  State<CalendarSharingScreen> createState() => _CalendarSharingScreenState();
}

class _CalendarSharingScreenState extends State<CalendarSharingScreen> {
  CalendarSharingViewModel get vm => widget.viewModel;
  final _query = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    vm.add.addListener(_onSave);
    vm.remove.addListener(_onSave);
  }

  @override
  void dispose() {
    vm.add.removeListener(_onSave);
    vm.remove.removeListener(_onSave);
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onSave() {
    for (final c in [vm.add, vm.remove]) {
      if (c.error) {
        showErrorSnackBar(context, c.result);
        c.clearResult();
      }
    }
  }

  void _onQuery(String q) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => vm.search.execute(q),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([vm, vm.load, vm.add, vm.remove]),
    builder: (context, _) {
      final c = AppColors.of(context);
      final viewers = vm.viewers;
      final busy = vm.add.running || vm.remove.running;
      if (!vm.enabled) {
        return const SettingsPage(
          title: 'Calendar sharing',
          children: [
            Padding(
              padding: EdgeInsets.all(24),
              child: Text('Calendar sharing needs a connection to Stall 10.'),
            ),
          ],
        );
      }
      return SettingsPage(
        title: 'Calendar sharing',
        children: [
          if (viewers == null)
            vm.load.error
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        const Text("Couldn't load who you share with."),
                        TextButton(
                          onPressed: vm.load.execute,
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  )
                : const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  )
          else ...[
            SettingsGroup(
              title: 'Shared with',
              footer:
                  'They see your personal events in their schedule: the '
                  'title, type, time and place, never your notes. Team '
                  "events aren't included. Remove someone and they stop "
                  'seeing it straight away.',
              children: [
                if (viewers.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      "You aren't sharing your calendar with anyone.",
                      style: TextStyle(color: c.muted),
                    ),
                  ),
                for (final v in viewers)
                  _PersonTile(
                    key: ValueKey(v.uid),
                    person: v,
                    trailing: TextButton(
                      onPressed: busy ? null : () => vm.remove.execute(v),
                      child: const Text('Remove'),
                    ),
                  ),
              ],
            ),
            if (!vm.full)
              SettingsGroup(
                title: 'Add someone',
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                    child: TextField(
                      controller: _query,
                      enabled: !busy,
                      textInputAction: TextInputAction.search,
                      decoration: const InputDecoration(
                        hintText: 'Name or username',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: _onQuery,
                    ),
                  ),
                  for (final p in vm.results)
                    _PersonTile(
                      key: ValueKey('r-${p.uid}'),
                      person: CalendarPerson(
                        uid: p.uid,
                        name: p.name,
                        username: p.username,
                        photoUrl: p.photoUrl,
                      ),
                      trailing: TextButton(
                        onPressed: busy
                            ? null
                            : () {
                                _query.clear();
                                vm.add.execute(
                                  CalendarPerson(
                                    uid: p.uid,
                                    name: p.name,
                                    username: p.username,
                                    photoUrl: p.photoUrl,
                                  ),
                                );
                              },
                        child: const Text('Share'),
                      ),
                    ),
                ],
              )
            else
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'You can share with up to '
                  '${CalendarSharingViewModel.maxViewers} people.',
                  style: TextStyle(color: c.muted),
                ),
              ),
          ],
        ],
      );
    },
  );
}

class _PersonTile extends StatelessWidget {
  const _PersonTile({super.key, required this.person, required this.trailing});

  final CalendarPerson person;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return ListTile(
      leading: PersonAvatar(name: person.name, photoUrl: person.photoUrl),
      title: Text(person.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: person.username == null
          ? null
          : Text('@${person.username}', style: TextStyle(color: c.muted)),
      trailing: trailing,
    );
  }
}
