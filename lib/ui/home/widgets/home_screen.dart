import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/play.dart';
import '../../../domain/models/ranking.dart';
import '../../../domain/models/team.dart';
import '../../../domain/models/schedule_entry.dart';
import '../../../domain/models/tournament.dart';
import '../../../routing/routes.dart';
import '../../../utils/result.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/brand.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/status_views.dart';
import '../../core/ui/usau_attribution.dart';
import '../../playbook/widgets/field_geometry.dart';
import '../../playbook/widgets/field_painter.dart';
import '../../playbook/widgets/play_canvas.dart';
import '../../schedule/widgets/event_style.dart';
import '../../schedule/widgets/schedule_widgets.dart';
import '../../teams/widgets/join_team_dialog.dart';
import '../../tournaments/widgets/tournament_widgets.dart' show formatDateRange;
import '../view_models/home_viewmodel.dart';

const _radius = 20.0;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.viewModel});

  final HomeViewModel viewModel;

  /// Content width at which home switches from one column to a dashboard.
  static const dashboardBreakpoint = 960.0;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  HomeViewModel get vm => widget.viewModel;

  @override
  void initState() {
    super.initState();
    vm.joinTeam.addListener(_onJoin);
  }

  @override
  void dispose() {
    vm.joinTeam.removeListener(_onJoin);
    super.dispose();
  }

  void _onJoin() {
    final cmd = vm.joinTeam;
    switch (cmd.result) {
      case Ok<String>(:final value):
        cmd.clearResult();
        context.go(Routes.team(value));
      case Error<String>():
        showErrorSnackBar(context, cmd.result);
        cmd.clearResult();
      case null:
        break;
    }
  }

  Future<void> _join() async {
    final code = await showDialog<String>(
      context: context,
      builder: (_) => const JoinTeamDialog(),
    );
    if (code != null) vm.joinTeam.execute(code);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: vm,
          builder: (context, _) => LayoutBuilder(
            builder: (context, constraints) =>
                constraints.maxWidth >= HomeScreen.dashboardBreakpoint
                ? _dashboard(context)
                : _column(context),
          ),
        ),
      ),
    );
  }

  /// Phone and narrow-window layout: every section in one scrolling column.
  Widget _column(BuildContext context) {
    return ConstrainedContent(
      maxWidth: 640,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          _Header(viewModel: vm),
          const SizedBox(height: 20),
          _weekSection(context),
          const SizedBox(height: 28),
          _teamSection(context),
          const SizedBox(height: 28),
          _playbookSection(context),
          const SizedBox(height: 28),
          _eventsSection(context),
          const SizedBox(height: 28),
          _rankingsSection(context),
        ],
      ),
    );
  }

  /// Desktop layout: the header across the top, then a wide column for the
  /// schedule and playbook beside a narrower one for team and rankings.
  Widget _dashboard(BuildContext context) {
    return ConstrainedContent(
      maxWidth: 1320,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(32, 16, 32, 32),
        children: [
          _Header(viewModel: vm),
          const SizedBox(height: 28),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _weekSection(context),
                    const SizedBox(height: 28),
                    _playbookSection(context),
                    const SizedBox(height: 28),
                    _eventsSection(context),
                  ],
                ),
              ),
              const SizedBox(width: 28),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _teamSection(context),
                    const SizedBox(height: 28),
                    _rankingsSection(context),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _weekSection(BuildContext context) => _Section(
    header: _SectionHeader(
      title: 'This week',
      action: 'Full schedule',
      onTap: () => context.go(Routes.schedule),
    ),
    children: [_WeekOutlook(viewModel: vm)],
  );

  Widget _teamSection(BuildContext context) {
    final team = vm.selectedTeam;
    return _Section(
      header: _SectionHeader(
        title: vm.teams.length > 1 ? 'My teams' : 'My team',
        action: 'Team hub',
        onTap: () => context.go(Routes.teams),
      ),
      children: [
        if (!vm.teamsLoaded)
          const _MutedCard(text: 'Loading your teams…')
        else if (team == null)
          ListenableBuilder(
            listenable: vm.joinTeam,
            builder: (context, _) => _JoinTeamCard(
              joining: vm.joinTeam.running,
              onJoin: _join,
              onCreate: () => context.go(Routes.createTeam),
            ),
          )
        else ...[
          if (vm.teams.length > 1) ...[
            _TeamChips(viewModel: vm),
            const SizedBox(height: 10),
          ],
          _TeamCard(
            team: team,
            next: vm.nextEventFor(team),
            onTap: () => context.go(Routes.team(team.id)),
          ),
        ],
      ],
    );
  }

  Widget _playbookSection(BuildContext context) {
    final team = vm.selectedTeam;
    return _Section(
      header: _SectionHeader(
        title: 'Playbook',
        action: team == null ? null : 'All plays',
        onTap: team == null
            ? null
            : () => context.go(Routes.team(team.id, tab: 'playbook')),
      ),
      children: [
        if (team != null && vm.plays.isNotEmpty)
          _PlayStrip(
            team: team,
            plays: vm.plays,
            total: vm.playCount,
            canEdit: vm.canEdit(team),
          )
        else
          _PlaybookHero(team: team, canEdit: team != null && vm.canEdit(team)),
      ],
    );
  }

  Widget _eventsSection(BuildContext context) => _Section(
    header: _SectionHeader(
      title: 'Coming up',
      action: 'Schedule',
      onTap: () => context.go(Routes.schedule),
    ),
    children: [_EventsSection(viewModel: vm)],
  );

  Widget _rankingsSection(BuildContext context) => _Section(
    header: _SectionHeader(
      title: 'Rankings',
      action: 'Full rankings',
      onTap: () => context.go(Routes.rankings),
    ),
    children: [
      _RankingsSection(viewModel: vm),
      const SizedBox(height: 8),
      const UsauAttribution(),
    ],
  );
}

/// A titled home section: header above its content.
class _Section extends StatelessWidget {
  const _Section({required this.header, required this.children});

  final Widget header;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [header, ...children],
  );
}

TextStyle _heading(BuildContext context, double size, {Color? color}) =>
    TextStyle(
      fontFamily: headingFont,
      fontWeight: FontWeight.w800,
      fontSize: size,
      height: 1.0,
      letterSpacing: 0.2,
      color: color ?? AppColors.of(context).ink,
    );

TextStyle _eyebrow(Color color) => TextStyle(
  fontSize: 11,
  fontWeight: FontWeight.w600,
  letterSpacing: 0.8,
  color: color,
);

class _Header extends StatelessWidget {
  const _Header({required this.viewModel});

  final HomeViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final vm = viewModel;
    final photo = vm.user?.photoUrl;
    final days = vm.daysUntilNext;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            InkWell(
              customBorder: const CircleBorder(),
              onTap: () => context.push(Routes.profile),
              child: CircleAvatar(
                radius: 20,
                backgroundColor: c.feature,
                foregroundColor: c.onFeature,
                backgroundImage: photo == null ? null : NetworkImage(photo),
                child: photo == null
                    ? Text(
                        vm.initials.toUpperCase(),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      )
                    : null,
              ),
            ),
            const Expanded(child: Center(child: UltiUpWordmark())),
            IconButton(
              tooltip: vm.unreadMessages == 0
                  ? 'Messages'
                  : 'Messages, ${vm.unreadMessages} unread',
              onPressed: () => context.push(Routes.messages),
              icon: Badge(
                isLabelVisible: vm.unreadMessages > 0,
                label: Text('${vm.unreadMessages}'),
                backgroundColor: c.accent,
                child: const Icon(Icons.chat_bubble_outline),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          DateFormat('EEEE, MMM d').format(vm.today).toUpperCase(),
          style: _eyebrow(c.muted),
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text(
                "LET'S GO, ${vm.firstName.toUpperCase()}.",
                style: _heading(context, 38),
              ),
            ),
            if (days != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4, left: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.event_outlined, size: 15, color: c.accent),
                    const SizedBox(width: 4),
                    Text(
                      days == 0 ? 'Event today' : '$days days out',
                      style: TextStyle(
                        color: c.accent,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.action, this.onTap});

  final String title;
  final String? action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final action = this.action;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(title.toUpperCase(), style: _heading(context, 24)),
          ),
          if (action != null)
            InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      action,
                      style: TextStyle(
                        color: c.accent,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(Icons.north_east, size: 14, color: c.accent),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Rounded card used by most home sections.
class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.onTap, this.padding});

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Material(
      color: c.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_radius),
        side: BorderSide(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: padding ?? const EdgeInsets.all(14),
          child: child,
        ),
      ),
    );
  }
}

// This week ----------------------------------------------------------------

class _WeekOutlook extends StatelessWidget {
  const _WeekOutlook({required this.viewModel});

  static const maxRows = 5;

  final HomeViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final vm = viewModel;
    final events = vm.weekEvents;
    final team = vm.selectedTeam;
    final today = vm.weekDays.first;
    return _Panel(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (final day in vm.weekDays)
                Expanded(
                  child: WeekDayCell(
                    day: day,
                    entries: vm.eventsOn(day),
                    isToday: DateUtils.isSameDay(day, today),
                    onTap: () => context.go(Routes.schedule),
                  ),
                ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(6, 6, 6, 8),
            child: ScheduleLegend(),
          ),
          Divider(height: 1, color: c.border),
          if (events.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 12, 6, 6),
              child: Text(
                'Nothing scheduled this week. Add a workout, pickup '
                'game or ${team == null ? 'other event' : 'team event'}.',
                style: TextStyle(color: c.muted),
              ),
            )
          else ...[
            const SizedBox(height: 4),
            for (final e in events.take(maxRows))
              ScheduleEventRow(entry: e, showTeamName: vm.teams.length > 1),
            if (events.length > maxRows)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
                child: Text(
                  '+${events.length - maxRows} more this week',
                  style: TextStyle(fontSize: 12, color: c.muted),
                ),
              ),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => context.push(Routes.newMyEvent()),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add event'),
            ),
          ),
        ],
      ),
    );
  }
}

// My team ------------------------------------------------------------------

class _TeamChips extends StatelessWidget {
  const _TeamChips({required this.viewModel});

  final HomeViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final selected = viewModel.selectedTeam?.id;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final t in viewModel.teams)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(t.name),
                selected: t.id == selected,
                onSelected: (_) => viewModel.selectTeam(t.id),
              ),
            ),
        ],
      ),
    );
  }
}

String _initials(String name) => name
    .split(RegExp(r'\s+'))
    .where((w) => w.isNotEmpty)
    .take(2)
    .map((w) => w[0].toUpperCase())
    .join();

class _TeamCard extends StatelessWidget {
  const _TeamCard({
    required this.team,
    required this.next,
    required this.onTap,
  });

  final Team team;
  final ScheduleEntry? next;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final next = this.next?.event;
    return _Panel(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.feature,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              _initials(team.name),
              style: _heading(context, 24, color: c.onFeature).copyWith(
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  team.name,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: c.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    '${team.members.length} '
                        '${team.members.length == 1 ? 'member' : 'members'}',
                    '${team.level.label} ${team.division.label}',
                    if (team.city.isNotEmpty) team.city,
                  ].join(' · '),
                  style: TextStyle(fontSize: 13, color: c.muted),
                ),
                if (next != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Next: ${next.type.label} · '
                    '${DateFormat.MMMEd().add_jm().format(next.startsAt)}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: c.accent,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: c.muted),
        ],
      ),
    );
  }
}

class _JoinTeamCard extends StatelessWidget {
  const _JoinTeamCard({
    required this.joining,
    required this.onJoin,
    required this.onCreate,
  });

  final bool joining;
  final VoidCallback onJoin;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Material(
      color: c.feature,
      borderRadius: BorderRadius.circular(_radius),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('NO TEAM YET', style: _eyebrow(c.onFeatureMuted)),
            const SizedBox(height: 6),
            Text(
              'JOIN YOUR TEAM.',
              style: _heading(context, 30, color: c.onFeature),
            ),
            const SizedBox(height: 6),
            Text(
              'Get the schedule, playbook and stats your team shares. '
              'Ask a coach for the invite code, or start your own team.',
              style: TextStyle(color: c.onFeatureMuted),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: c.accent,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: joining ? null : onJoin,
                  icon: const Icon(Icons.group_add_outlined, size: 18),
                  label: const Text('Join with code'),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: c.onFeature,
                    side: BorderSide(color: c.onFeatureMuted),
                  ),
                  onPressed: onCreate,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Create team'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// Playbook -----------------------------------------------------------------

class _PlayStrip extends StatelessWidget {
  const _PlayStrip({
    required this.team,
    required this.plays,
    required this.total,
    required this.canEdit,
  });

  final Team team;
  final List<Play> plays;
  final int total;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final more = total - plays.length;
    return SizedBox(
      height: 210,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final p in plays)
            _PlayTile(
              play: p,
              onTap: () => context.go(Routes.play(team.id, p.id)),
            ),
          if (more > 0)
            _StripAction(
              icon: Icons.menu_book_outlined,
              label: '+$more more',
              onTap: () => context.go(Routes.team(team.id, tab: 'playbook')),
            ),
          if (canEdit)
            _StripAction(
              icon: Icons.add,
              label: 'New play',
              onTap: () => context.go(Routes.newPlay(team.id)),
            ),
        ],
      ),
    );
  }
}

class _PlayTile extends StatelessWidget {
  const _PlayTile({required this.play, required this.onTap});

  final Play play;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: SizedBox(
        width: 136,
        child: _Panel(
          onTap: onTap,
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: IgnorePointer(child: PlayDiagram(play: play)),
              ),
              const SizedBox(height: 6),
              Text(
                play.name.isEmpty ? 'Untitled play' : play.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w700, color: c.ink),
              ),
              Text(
                play.category.label,
                style: TextStyle(fontSize: 12, color: c.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StripAction extends StatelessWidget {
  const _StripAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: SizedBox(
        width: 110,
        child: _Panel(
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                backgroundColor: c.accentSoft,
                foregroundColor: c.accent,
                child: Icon(icon),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w600, color: c.ink),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown when there are no plays to preview yet.
class _PlaybookHero extends StatelessWidget {
  const _PlaybookHero({required this.team, required this.canEdit});

  final Team? team;
  final bool canEdit;

  static const _emptyField = Play(id: '', name: '');

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final team = this.team;
    final (label, route) = switch (team) {
      null => ('Create team', Routes.createTeam),
      _ when canEdit => ('Draw first play', Routes.newPlay(team.id)),
      _ => ('Open playbook', Routes.team(team.id, tab: 'playbook')),
    };
    // A landscape field is long side x short side.
    const fieldHeight = 100.0;
    const fieldWidth = fieldHeight / FieldGeometry.aspect;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 190),
      child: Material(
        color: c.feature,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // Draw the field at its real proportions and crop it to the card
            // so the lines aren't stretched.
            Positioned.fill(
              child: FittedBox(
                fit: BoxFit.cover,
                alignment: Alignment.centerRight,
                child: SizedBox(
                  width: fieldWidth,
                  height: fieldHeight,
                  child: CustomPaint(
                    painter: FieldPainter(play: _emptyField, horizontal: true),
                  ),
                ),
              ),
            ),
            // Fade the field into the card so the text stays readable.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      c.feature.withValues(alpha: 0.95),
                      c.feature.withValues(alpha: 0.7),
                      c.feature.withValues(alpha: 0.1),
                    ],
                    stops: const [0, 0.55, 1],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    team == null ? 'YOUR PLAYBOOK' : team.name.toUpperCase(),
                    style: _eyebrow(c.onFeatureMuted),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'DRAW UP THE\nFIRST PLAY.',
                    style: _heading(context, 32, color: c.onFeature),
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: c.accent,
                      foregroundColor: Colors.white,
                      shape: const StadiumBorder(),
                    ),
                    iconAlignment: IconAlignment.end,
                    icon: const Icon(Icons.arrow_forward, size: 18),
                    label: Text(label),
                    onPressed: () => context.go(route),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Events -------------------------------------------------------------------

class _EventsSection extends StatelessWidget {
  const _EventsSection({required this.viewModel});

  final HomeViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final c = AppColors.of(context);
    final upcoming = vm.upcomingEvents;
    final other = vm.otherEvents;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (upcoming.isEmpty)
          _MutedCard(
            text: vm.teams.isEmpty
                ? 'Nothing coming up. Add your own events, or join a team to '
                      'see its practices, scrimmages and tournaments.'
                : 'Nothing coming up.',
          )
        else
          for (final e in upcoming) ...[
            _ScheduleEventCard(entry: e, showTeamName: vm.teams.length > 1),
            const SizedBox(height: 10),
          ],
        const SizedBox(height: 4),
        _Panel(
          padding: EdgeInsets.zero,
          child: SwitchListTile(
            value: vm.showOtherEvents,
            onChanged: vm.setShowOtherEvents,
            title: Text(
              'Show other events',
              style: TextStyle(fontWeight: FontWeight.w600, color: c.ink),
            ),
            subtitle: const Text('Upcoming USA Ultimate tournaments'),
          ),
        ),
        if (vm.showOtherEvents) ...[
          const SizedBox(height: 10),
          if (other.isEmpty)
            const _MutedCard(text: 'No upcoming tournaments.')
          else
            for (final t in other) ...[
              _TournamentCard(
                tournament: t,
                onTap: () => context.go(Routes.tournament(t.id)),
              ),
              const SizedBox(height: 10),
            ],
        ],
      ],
    );
  }
}

class _DateTile extends StatelessWidget {
  const _DateTile({required this.date, required this.color, this.fill});

  final DateTime? date;
  final Color color;
  final Color? fill;

  @override
  Widget build(BuildContext context) {
    final date = this.date;
    return Container(
      width: 52,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: fill ?? color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            date == null ? 'TBA' : DateFormat.MMM().format(date).toUpperCase(),
            style: _eyebrow(color),
          ),
          if (date != null)
            Text('${date.day}', style: _heading(context, 26, color: color)),
        ],
      ),
    );
  }
}

class _ScheduleEventCard extends StatelessWidget {
  const _ScheduleEventCard({required this.entry, required this.showTeamName});

  final ScheduleEntry entry;
  final bool showTeamName;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final e = entry.event;
    final color = scheduleColor(context, entry);
    return _Panel(
      padding: const EdgeInsets.all(12),
      onTap: () => context.push(Routes.scheduleEvent(entry)),
      child: Row(
        children: [
          _DateTile(date: e.startsAt, color: color),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: c.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    DateFormat.E().format(e.startsAt),
                    eventTimeRange(e),
                    if (e.location.isNotEmpty) e.location,
                  ].join(' · '),
                  style: TextStyle(fontSize: 13, color: c.muted),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(e.type.icon, size: 14, color: color),
                    const SizedBox(width: 4),
                    Text(
                      e.type.label,
                      style: TextStyle(
                        fontSize: 13,
                        color: color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: ScheduleTag(
                        entry: entry,
                        showTeamName: showTeamName,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: c.muted),
        ],
      ),
    );
  }
}

class _TournamentCard extends StatelessWidget {
  const _TournamentCard({required this.tournament, required this.onTap});

  final Tournament tournament;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final t = tournament;
    final tags = [
      if (t.competitionLevel.isNotEmpty) t.competitionLevel,
      if (t.divisions.isNotEmpty) t.divisions.join(', '),
    ].join(' · ');
    return _Panel(
      padding: const EdgeInsets.all(12),
      onTap: onTap,
      child: Row(
        children: [
          _DateTile(date: t.startDate, color: c.accent, fill: c.accentSoft),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: c.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    formatDateRange(t.startDate, t.endDate),
                    if (t.location.isNotEmpty) t.location,
                  ].join(' · '),
                  style: TextStyle(fontSize: 13, color: c.muted),
                ),
                if (tags.isNotEmpty)
                  Text(
                    tags,
                    style: TextStyle(
                      fontSize: 13,
                      color: c.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
          Icon(Icons.north_east, size: 20, color: c.ink),
        ],
      ),
    );
  }
}

// Rankings -----------------------------------------------------------------

void _openTeam(BuildContext context, RankingEntry entry) {
  if (entry.teamUrl.isEmpty) return;
  context.go(Routes.usauTeam(entry.teamUrl, name: entry.teamName));
}

class _RankingsSection extends StatelessWidget {
  const _RankingsSection({required this.viewModel});

  final HomeViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final vm = viewModel;
    final division = vm.featuredDivision;
    if (division == null) {
      return Material(
        color: c.feature,
        borderRadius: BorderRadius.circular(_radius),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              if (vm.rankingsLoaded)
                Icon(Icons.leaderboard_outlined, color: c.onFeatureMuted)
              else
                SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: c.onFeatureMuted,
                  ),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  vm.rankingsLoaded
                      ? "USA Ultimate rankings aren't available right now."
                      : 'Loading USA Ultimate rankings…',
                  style: TextStyle(color: c.onFeatureMuted),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final mine = vm.myRanking;
    final below = vm.myRankingBelowTopTen;
    final updated = division.updatedAt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (vm.divisions.length > 1) ...[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final d in vm.divisions)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(d.label),
                      selected: d.key == division.key,
                      onSelected: (_) => vm.selectDivision(d.key),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        Material(
          color: c.feature,
          borderRadius: BorderRadius.circular(_radius),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'USA ULTIMATE / ${division.label.toUpperCase()}',
                        style: _eyebrow(c.onFeatureMuted),
                      ),
                    ),
                    if (mine != null)
                      Text('YOU: #${mine.rank}', style: _eyebrow(c.positive)),
                  ],
                ),
                const SizedBox(height: 14),
                if (division.entries.isEmpty)
                  Text(
                    'No teams ranked yet.',
                    style: TextStyle(color: c.onFeatureMuted),
                  )
                else
                  _Podium(entries: vm.podium, isMine: vm.isMine),
                if (vm.topTen.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Divider(height: 1, color: c.featureHighlight),
                  const SizedBox(height: 6),
                  for (final e in vm.topTen)
                    _RankingRow(entry: e, mine: vm.isMine(e)),
                ],
                if (below != null) ...[
                  Divider(height: 13, color: c.featureHighlight),
                  _RankingRow(entry: below, mine: true),
                ],
                const SizedBox(height: 8),
                Text(
                  [
                    '${division.entries.length} teams ranked',
                    if (updated != null)
                      'updated ${DateFormat.MMMd().format(updated.toLocal())}',
                  ].join(' · '),
                  style: TextStyle(fontSize: 12, color: c.onFeatureMuted),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Top three as podium steps, ordered 2 | 1 | 3.
class _Podium extends StatelessWidget {
  const _Podium({required this.entries, required this.isMine});

  final List<RankingEntry> entries;
  final bool Function(RankingEntry) isMine;

  static const _medals = [
    Color(0xFFE8B931), // gold
    Color(0xFFB8C2CC), // silver
    Color(0xFFCD8B5A), // bronze
  ];
  static const _heights = [150.0, 128.0, 114.0];

  @override
  Widget build(BuildContext context) {
    Widget step(int place) => Expanded(
      child: place < entries.length
          ? _PodiumStep(
              entry: entries[place],
              medal: _medals[place],
              height: MediaQuery.textScalerOf(context).scale(_heights[place]),
              mine: isMine(entries[place]),
            )
          : const SizedBox.shrink(),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        step(1),
        const SizedBox(width: 8),
        step(0),
        const SizedBox(width: 8),
        step(2),
      ],
    );
  }
}

class _PodiumStep extends StatelessWidget {
  const _PodiumStep({
    required this.entry,
    required this.medal,
    required this.height,
    required this.mine,
  });

  final RankingEntry entry;
  final Color medal;
  final double height;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final rating = entry.rating;
    return SizedBox(
      height: height,
      child: Material(
        color: c.featureHighlight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: mine ? c.positive : medal.withValues(alpha: 0.6),
            width: mine ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openTeam(context, entry),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 15,
                  backgroundColor: medal,
                  foregroundColor: const Color(0xFF1E2A36),
                  child: Text(
                    '${entry.rank}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                const Spacer(),
                Text(
                  entry.teamName,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.onFeature,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    height: 1.15,
                  ),
                ),
                if (rating != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    rating.toStringAsFixed(0),
                    style: TextStyle(color: c.onFeatureMuted, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RankingRow extends StatelessWidget {
  const _RankingRow({required this.entry, required this.mine});

  final RankingEntry entry;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final rating = entry.rating;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _openTeam(context, entry),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color: mine ? c.featureHighlight : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              child: Text(
                entry.rank.toString().padLeft(2, '0'),
                style: TextStyle(
                  color: mine ? c.positive : c.onFeatureMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: Text(
                entry.teamName,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: c.onFeature,
                  fontWeight: mine ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            if (mine)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text('YOU', style: _eyebrow(c.positive)),
              ),
            if (rating != null)
              Text(
                rating.toStringAsFixed(0),
                style: TextStyle(
                  color: c.onFeature,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MutedCard extends StatelessWidget {
  const _MutedCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => _Panel(
    padding: const EdgeInsets.all(16),
    child: Text(text, style: TextStyle(color: AppColors.of(context).muted)),
  );
}
