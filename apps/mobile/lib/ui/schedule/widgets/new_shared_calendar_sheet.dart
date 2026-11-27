import 'dart:async';

import 'package:flutter/material.dart';

import '../../../domain/models/calendar.dart';
import '../../../domain/models/player_profile.dart';
import '../../calendar/widgets/calendars_screen.dart' show CalendarColorChoice;
import '../../core/themes/theme.dart';
import '../../core/ui/layout.dart' show PersonAvatar;
import '../view_models/event_editor_viewmodel.dart';
import '../../core/ui/app_segmented_button.dart';

/// From the event editor: a new calendar to share, made on the spot (name,
/// color, who to invite and what they may do), so sharing an event doesn't
/// need a trip to Calendars first. [search] finds people by name or
/// username. Returns null when cancelled.
Future<NewSharedCalendar?> showNewSharedCalendarSheet(
  BuildContext context, {
  required Future<List<PlayerProfile>> Function(String query) search,
}) => showModalBottomSheet<NewSharedCalendar>(
  context: context,
  sheetAnimationStyle: AppMotion.sheetStyle(context),
  isScrollControlled: true,
  showDragHandle: true,
  useSafeArea: true,
  builder: (_) => _NewSharedCalendarSheet(search: search),
);

class _NewSharedCalendarSheet extends StatefulWidget {
  const _NewSharedCalendarSheet({required this.search});

  final Future<List<PlayerProfile>> Function(String query) search;

  @override
  State<_NewSharedCalendarSheet> createState() =>
      _NewSharedCalendarSheetState();
}

class _NewSharedCalendarSheetState extends State<_NewSharedCalendarSheet> {
  final _name = TextEditingController();
  final _query = TextEditingController();
  var _color = CalendarColor.blue;
  var _role = CalendarRole.view;
  final _invite = <PlayerProfile>[];
  List<PlayerProfile> _results = const [];
  Timer? _debounce;
  var _asked = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _name.dispose();
    _query.dispose();
    super.dispose();
  }

  void _onQuery(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final ask = ++_asked;
      final found = await widget.search(q);
      if (!mounted || ask != _asked) return;
      setState(() => _results = found);
    });
  }

  void _add(PlayerProfile p) => setState(() {
    if (!_invite.any((x) => x.uid == p.uid)) _invite.add(p);
    _query.clear();
    _results = const [];
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final name = _name.text.trim();
    final shown = [
      for (final p in _results)
        if (!_invite.any((x) => x.uid == p.uid)) p,
    ];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          const Text(
            'New shared calendar',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            "This event goes on it. People see it once they accept; you can "
            'add more later from Calendars.',
            style: TextStyle(fontSize: 13, color: c.muted),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            autofocus: true,
            maxLength: 60,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'e.g. Family, Carpool',
            ),
            onChanged: (_) => setState(() {}),
          ),
          CalendarColorChoice(
            value: _color,
            onChanged: (v) => setState(() => _color = v),
          ),
          const SizedBox(height: 16),
          AppSegmentedButton<CalendarRole>(
            segments: [
              for (final r in CalendarRole.shareable)
                ButtonSegment(value: r, label: Text(r.label)),
            ],
            selected: {_role},
            onSelectionChanged: (s) => setState(() => _role = s.first),
          ),
          const SizedBox(height: 4),
          Text(
            _role == CalendarRole.edit
                ? 'They can see and add events.'
                : 'They see titles, times and places, not notes.',
            style: TextStyle(fontSize: 12, color: c.muted),
          ),
          const SizedBox(height: 12),
          if (_invite.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final p in _invite)
                  InputChip(
                    avatar: PersonAvatar(name: p.name, photoUrl: p.photoUrl),
                    label: Text(p.name),
                    onDeleted: () => setState(() => _invite.remove(p)),
                  ),
              ],
            ),
          TextField(
            controller: _query,
            decoration: const InputDecoration(
              labelText: 'Invite people',
              hintText: 'Name or username',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: _onQuery,
          ),
          for (final p in shown.take(6))
            ListTile(
              key: ValueKey('person-${p.uid}'),
              contentPadding: EdgeInsets.zero,
              leading: PersonAvatar(name: p.name, photoUrl: p.photoUrl),
              title: Text(p.name),
              subtitle: p.username == null
                  ? null
                  : Text('@${p.username}', style: TextStyle(color: c.muted)),
              trailing: TextButton(
                onPressed: () => _add(p),
                child: const Text('Add'),
              ),
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: name.isEmpty
                ? null
                : () => Navigator.pop(context, (
                    name: name,
                    color: _color,
                    invite: List.of(_invite),
                    role: _role,
                  )),
            child: Text(
              _invite.isEmpty ? 'Create calendar' : 'Create and invite',
            ),
          ),
        ],
      ),
    );
  }
}
