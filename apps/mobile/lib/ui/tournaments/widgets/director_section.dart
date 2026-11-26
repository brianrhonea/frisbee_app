import 'dart:async';

import 'package:flutter/material.dart';

import '../../../domain/models/hosted_tournament.dart';
import '../../../domain/models/player_profile.dart';
import '../../core/themes/theme.dart';
import '../view_models/hosted_tournament_form_viewmodel.dart';
import '../../core/ui/app_segmented_button.dart';

/// The event form's Director step (the website's DirectorStep): a Stall 10
/// member, found by name, or someone not on Stall 10 with their name,
/// email and phone. The director is a contact; it gives no rights.
class DirectorSection extends StatefulWidget {
  const DirectorSection({super.key, required this.viewModel});

  final HostedTournamentFormViewModel viewModel;

  @override
  State<DirectorSection> createState() => _DirectorSectionState();
}

class _DirectorSectionState extends State<DirectorSection> {
  late bool _member =
      widget.viewModel.director == null || widget.viewModel.director!.isMember;
  final _query = TextEditingController();
  late final _name = TextEditingController(text: _outside?.name ?? '');
  late final _email = TextEditingController(text: _outside?.email ?? '');
  late final _phone = TextEditingController(text: _outside?.phone ?? '');
  List<PlayerProfile> _hits = const [];
  Timer? _debounce;

  TournamentDirector? get _outside {
    final d = widget.viewModel.director;
    return d != null && !d.isMember ? d : null;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _search(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final hits = await widget.viewModel.searchPeople(q);
      if (mounted && _query.text == q) setState(() => _hits = hits);
    });
  }

  void _setOutside() {
    final name = _name.text.trim();
    widget.viewModel.setDirector(
      name.isEmpty && _email.text.trim().isEmpty && _phone.text.trim().isEmpty
          ? null
          : TournamentDirector(
              name: _name.text,
              email: _email.text,
              phone: _phone.text,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    final c = AppColors.of(context);
    final d = vm.director;
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Who runs the event on the day. Teams see them on the event '
            'page as the person to contact. Optional, and it gives no '
            'organizer rights.',
            style: TextStyle(fontSize: 12.5, color: c.muted),
          ),
          const SizedBox(height: 12),
          AppSegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('On Stall 10')),
              ButtonSegment(value: false, label: Text('Not on Stall 10')),
            ],
            selected: {_member},
            onSelectionChanged: (s) {
              setState(() => _member = s.first);
              if (_member) {
                if (d != null && !d.isMember) vm.setDirector(null);
              } else {
                _setOutside();
              }
            },
          ),
          const SizedBox(height: 12),
          if (_member) ...[
            if (d != null && d.isMember)
              ListTile(
                key: const Key('director-picked'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_outline),
                title: Text(d.name),
                subtitle: d.uid == vm.myUid ? const Text('You') : null,
                trailing: IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.close),
                  onPressed: () => vm.setDirector(null),
                ),
              )
            else ...[
              if (vm.myUid case final me? when vm.myName.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    key: const Key('director-me'),
                    icon: const Icon(Icons.person_outline),
                    label: const Text("It's me"),
                    onPressed: () => vm.setDirector(
                      TournamentDirector(uid: me, name: vm.myName),
                    ),
                  ),
                ),
              if (vm.canSearchPeople) ...[
                const SizedBox(height: 8),
                TextField(
                  key: const Key('director-search'),
                  controller: _query,
                  decoration: const InputDecoration(
                    labelText: 'Find a member',
                    hintText: 'Name or @username',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: _search,
                ),
                for (final p in _hits)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(p.name),
                    subtitle: p.username == null
                        ? null
                        : Text('@${p.username}'),
                    onTap: () {
                      vm.setDirector(
                        TournamentDirector(uid: p.uid, name: p.name),
                      );
                      _query.clear();
                      setState(() => _hits = const []);
                    },
                  ),
              ],
            ],
          ] else ...[
            TextField(
              key: const Key('director-name'),
              controller: _name,
              maxLength: TournamentDirector.maxName,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name'),
              onChanged: (_) => _setOutside(),
            ),
            TextField(
              key: const Key('director-email'),
              controller: _email,
              maxLength: TournamentDirector.maxEmail,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email (optional)'),
              onChanged: (_) => _setOutside(),
            ),
            TextField(
              key: const Key('director-phone'),
              controller: _phone,
              maxLength: TournamentDirector.maxPhone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone (optional)'),
              onChanged: (_) => _setOutside(),
            ),
            Text(
              'Only signed-in members see the email and phone.',
              style: TextStyle(fontSize: 12.5, color: c.muted),
            ),
          ],
        ],
      ),
    );
  }
}
