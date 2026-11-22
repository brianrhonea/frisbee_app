import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/discord/discord_import_repository.dart';
import 'package:frisbee_app/domain/models/chat.dart';
import 'package:frisbee_app/domain/models/discord_import.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/teams/view_models/discord_import_viewmodel.dart';
import 'package:frisbee_app/ui/teams/widgets/discord_import_screen.dart';
import 'package:frisbee_app/utils/result.dart';

import '../testing/fakes.dart';

/// A trimmed copy of what the preview returns for the shared made-up
/// template (packages/shared/fixtures/discord/template_plan.json, which
/// test/shared_fixtures/discord_fixtures_test.dart uses in full).
final planMap = <String, dynamic>{
  'serverName': 'Rockets Ultimate',
  'roles': [
    {
      'key': '4',
      'name': 'Admin',
      'color': 0xFFE74C3C,
      'position': 0,
      'perms': [
        'manageTeam',
        'manageMembers',
        'manageChats',
        'manageEvents',
        'moderate',
      ],
    },
    {
      'key': '3',
      'name': 'Captains',
      'color': 0xFF3498DB,
      'position': 1,
      'perms': ['manageMembers', 'manageChats', 'manageEvents'],
    },
    {
      'key': '1',
      'name': 'Handlers',
      'color': 0,
      'position': 2,
      'perms': <String>[],
    },
  ],
  'folders': [
    {
      'key': '10',
      'name': 'Info',
      'position': 0,
      'readRoles': ['everyone'],
      'writeRoles': ['4', '3'],
    },
    {
      'key': '20',
      'name': 'Team',
      'position': 1,
      'readRoles': ['everyone'],
      'writeRoles': ['everyone'],
    },
  ],
  'rooms': [
    {
      'name': 'announcements',
      'folderKey': '10',
      'position': 0,
      'readRoles': ['everyone'],
      'writeRoles': ['4', '3'],
    },
    {
      'name': 'general',
      'folderKey': '20',
      'position': 0,
      'readRoles': ['everyone'],
      'writeRoles': ['everyone'],
    },
    {
      'name': 'handlers-only',
      'folderKey': '20',
      'position': 1,
      'readRoles': ['4', '1'],
      'writeRoles': ['4', '1'],
    },
    {
      'name': 'off-topic',
      'folderKey': null,
      'position': 0,
      'readRoles': ['everyone'],
      'writeRoles': ['everyone'],
    },
  ],
  'skipped': [
    {'name': 'Practice voice', 'reason': 'Voice channel'},
  ],
  'skippedRoles': <String>[],
};

class FakeDiscordImportRepository implements DiscordImportRepository {
  FakeDiscordImportRepository(this.teams, this.chats);

  final FakeTeamRepository teams;
  final FakeChatRepository chats;
  final links = <String>[];

  @override
  Future<Result<DiscordImportPlan>> preview(String teamId, String link) async {
    links.add(link);
    if (!link.contains('discord.new')) {
      return Result.error(Exception("Discord doesn't know that template."));
    }
    return Result.ok(DiscordImportPlan.fromMap(planMap));
  }

  @override
  Future<Result<void>> apply(
    Team team,
    DiscordImport import,
    String uid,
  ) async {
    await teams.saveRoles(
      team,
      roles: import.roles,
      memberRoles: team.memberRoles,
    );
    for (final f in import.folders) {
      chats.folders[f.id] = f;
      chats.teamOf['f:${f.id}'] = team.id;
    }
    for (final r in import.rooms) {
      await chats.saveRoom(team.id, r, uid);
    }
    chats.emit();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> applyToTeam(TeamChatImport import, String uid) async {
    final team = teams.teams[import.team.id]!;
    teams.teams[team.id] = team.copyWith(orgRoles: import.orgRoles);
    return apply(teams.teams[team.id]!, import.import, uid);
  }
}

void main() {
  final plan = DiscordImportPlan.fromMap(planMap);
  var n = 0;
  String ids() => 'id${++n}';

  setUp(() => n = 0);

  group('DiscordImportPlan', () {
    test('parses what the function returns', () {
      expect(plan.serverName, 'Rockets Ultimate');
      expect(plan.roles.map((r) => r.name), ['Admin', 'Captains', 'Handlers']);
      expect(plan.roles[1].permissions, {
        TeamPermission.manageMembers,
        TeamPermission.manageChats,
        TeamPermission.manageEvents,
      });
      expect(plan.rooms.last.folderKey, isNull);
      expect(plan.skippedChannels, ['Practice voice: Voice channel']);
    });
  });

  group('DiscordImport.of', () {
    final team = teamWith({'o': TeamRole.owner, 'p': TeamRole.player});

    test('maps template keys to new roles, folders and rooms', () {
      final i = DiscordImport.of(
        plan,
        team: team,
        folders: const [],
        rooms: [ChatRoom.general()],
        newId: ids,
      );
      expect(i.newRoles, ['Admin', 'Captains', 'Handlers']);
      final byName = {for (final r in i.roles.values) r.name: r};
      expect(byName['Admin']!.position, 0);
      expect(byName['Handlers']!.position, 2);
      expect(i.folders.map((f) => f.name), ['Info', 'Team']);
      final info = i.folders.first;
      expect(info.writeRoles, {byName['Admin']!.id, byName['Captains']!.id});
      expect(i.rooms.map((r) => r.name), [
        'announcements',
        'general',
        'handlers-only',
        'off-topic',
      ]);
      final handlersOnly = i.rooms[2];
      expect(handlersOnly.folderId, i.folders.last.id);
      expect(handlersOnly.position, 1);
      expect(handlersOnly.readRoles, {
        byName['Admin']!.id,
        byName['Handlers']!.id,
      });
      // "general" goes in the Team folder, so it doesn't clash with the
      // team's own General room; off-topic goes after it.
      expect(i.rooms[1].folderId, i.folders.last.id);
      expect(i.rooms.last.folderId, isNull);
      expect(i.rooms.last.position, 1);
      expect(i.alreadyHere, isEmpty);
      expect(i.isEmpty, isFalse);
    });

    test('importing again adds nothing', () {
      final first = DiscordImport.of(
        plan,
        team: team,
        folders: const [],
        rooms: const [],
        newId: ids,
      );
      final again = DiscordImport.of(
        plan,
        team: team.copyWith(roles: first.roles),
        folders: first.folders,
        rooms: first.rooms,
        newId: ids,
      );
      expect(again.isEmpty, isTrue);
      expect(again.alreadyHere, hasLength(4));
      expect(again.roles.keys, first.roles.keys);
    });

    test('reuses roles by name and stays within the role limit', () {
      final full = team.copyWith(
        roles: {
          'mine': const CustomRole(id: 'mine', name: 'handlers'),
          for (var i = 0; i < CustomRole.maxRoles - 2; i++)
            'r$i': CustomRole(id: 'r$i', name: 'Role $i', position: i + 1),
        },
      );
      final i = DiscordImport.of(
        plan,
        team: full,
        folders: const [],
        rooms: const [],
        newId: ids,
      );
      expect(i.newRoles, ['Admin']);
      expect(i.tooManyRoles, ['Captains']);
      expect(i.roles, hasLength(CustomRole.maxRoles));
      // Handlers maps to the team's own "handlers"; Captains is dropped
      // from access lists, narrowing access rather than widening it.
      final handlersOnly = i.rooms.firstWhere((r) => r.name == 'handlers-only');
      expect(handlersOnly.readRoles, contains('mine'));
      final announcements = i.rooms.first;
      expect(announcements.writeRoles, hasLength(1));
    });
  });

  group('DiscordImportViewModel', () {
    late FakeTeamRepository teams;
    late FakeChatRepository chats;
    late FakeDiscordImportRepository discord;

    DiscordImportViewModel load() => DiscordImportViewModel(
      teamId: 't1',
      teamRepository: teams,
      chatRepository: chats,
      discordImportRepository: discord,
      authRepository: FakeAuthRepository(user: testUser),
    );

    setUp(() {
      teams = FakeTeamRepository();
      chats = FakeChatRepository()..rooms['general'] = ChatRoom.general();
      discord = FakeDiscordImportRepository(teams, chats);
    });

    test('the owner previews and imports a template', () async {
      teams.teams['t1'] = teamWith({'u1': TeamRole.owner});
      final vm = load();
      await pumpEventQueue();
      expect(vm.loaded, isTrue);
      expect(vm.isOwner, isTrue);
      expect(vm.canPreview, isFalse);

      vm.setLink('https://example.com/nope');
      await vm.preview.execute();
      expect(vm.preview.error, isTrue);
      expect(vm.plan, isNull);

      vm.setLink(' https://discord.new/abc123 ');
      await vm.preview.execute();
      expect(discord.links.last, 'https://discord.new/abc123');
      expect(vm.plan!.serverName, 'Rockets Ultimate');
      expect(vm.import!.rooms, hasLength(4));
      expect(vm.canApply, isTrue);

      await vm.apply.execute();
      await pumpEventQueue();
      expect(vm.done, isTrue);
      expect(vm.canApply, isFalse);
      expect(teams.teams['t1']!.roles, hasLength(3));
      expect(chats.folders, hasLength(2));
      expect(chats.rooms, hasLength(5));
      // Everything's there now, so a second import would add nothing.
      expect(vm.import!.isEmpty, isTrue);
      vm.dispose();
    });

    test('the owner picks which channels to import', () async {
      teams.teams['t1'] = teamWith({'u1': TeamRole.owner});
      final vm = load();
      addTearDown(vm.dispose);
      await pumpEventQueue();
      vm.setLink('https://discord.new/abc123');
      await vm.preview.execute();

      // Everything is ticked to start with, grouped as Discord shows it.
      expect(vm.pickedCount, 4);
      expect(vm.channelGroups.map((g) => g.name), [null, 'Info', 'Team']);
      expect(vm.channelGroups.map((g) => g.rooms), [
        [3],
        [0],
        [1, 2],
      ]);

      // Untick the whole Info category and one Team channel.
      vm.setGroupPicked(vm.channelGroups[1], false);
      vm.setPicked(1, false);
      expect(vm.isPicked(0), isFalse);
      expect(vm.pickedCount, 2);
      expect(vm.import!.rooms.map((r) => r.name), [
        'handlers-only',
        'off-topic',
      ]);
      // Info has no channel left, so it isn't made; roles all still come.
      expect(vm.import!.folders.map((f) => f.name), ['Team']);
      expect(vm.import!.newRoles, hasLength(3));

      await vm.apply.execute();
      await pumpEventQueue();
      expect(vm.apply.error, isFalse);
      expect(
        chats.rooms.values.map((r) => r.name),
        unorderedEquals(['General', 'handlers-only', 'off-topic']),
      );
      expect(chats.folders.values.map((f) => f.name), ['Team']);

      // None leaves only what's already there: nothing new to import.
      vm.setAllPicked(false);
      expect(vm.import!.rooms, isEmpty);
      expect(vm.canApply, isFalse);
      // The rest can still come later.
      vm.setAllPicked(true);
      expect(vm.import!.rooms.map((r) => r.name), ['announcements', 'general']);
      expect(vm.canApply, isTrue);
      // Out of range is ignored.
      vm.setPicked(99, true);
      expect(vm.pickedCount, 4);
    });

    test('a new link starts the picking over', () async {
      teams.teams['t1'] = teamWith({'u1': TeamRole.owner});
      final vm = load();
      addTearDown(vm.dispose);
      await pumpEventQueue();
      vm.setLink('https://discord.new/abc123');
      await vm.preview.execute();
      vm.setAllPicked(false);
      vm.setLink('https://discord.new/other');
      expect(vm.picking, isNull);
      await vm.preview.execute();
      expect(vm.pickedCount, 4);
    });

    testWidgets('the screen lists channels by category with All and None', (
      tester,
    ) async {
      // Tall enough that every channel is on screen.
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      teams.teams['t1'] = teamWith({'u1': TeamRole.owner});
      final vm = load();
      addTearDown(vm.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: DiscordImportScreen(viewModel: vm),
        ),
      );
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'https://discord.new/a');
      await tester.pump();
      await tester.tap(find.text('Preview'));
      await tester.pumpAndSettle();

      expect(find.text('Pick channels'), findsOneWidget);
      expect(find.textContaining('4 of 4 text channels picked'), findsOne);
      expect(find.text('INFO'), findsOneWidget);
      expect(find.text('TEAM'), findsOneWidget);
      expect(find.text('# handlers-only'), findsOneWidget);

      await tester.tap(find.text('None'));
      await tester.pump();
      expect(find.textContaining('0 of 4 text channels picked'), findsOne);
      expect(vm.import!.rooms, isEmpty);

      // A category's box ticks all its channels.
      await tester.tap(find.text('TEAM'));
      await tester.pump();
      expect(vm.import!.rooms.map((r) => r.name), ['general', 'handlers-only']);
      await tester.tap(find.text('# general'));
      await tester.pump();
      expect(vm.import!.rooms.map((r) => r.name), ['handlers-only']);
      final team = tester.widget<CheckboxListTile>(
        find.widgetWithText(CheckboxListTile, 'TEAM'),
      );
      expect(team.value, isNull);

      await tester.tap(find.text('All'));
      await tester.pump();
      expect(vm.pickedCount, 4);
    });

    test('only the owner may import', () async {
      teams.teams['t1'] = teamWith({'o': TeamRole.owner, 'u1': TeamRole.coach});
      final vm = load();
      await pumpEventQueue();
      vm.setLink('https://discord.new/abc123');
      expect(vm.isOwner, isFalse);
      expect(vm.canPreview, isFalse);
      vm.dispose();
    });
  });

  test(
    'a community sends team rooms to its teams and moves old copies',
    () async {
      final teams = FakeTeamRepository();
      final chats = FakeChatRepository();
      final discord = FakeDiscordImportRepository(teams, chats);
      teams.teams['org'] = Team(
        id: 'org',
        name: 'Rockets',
        division: Division.mixed,
        level: CompetitionLevel.club,
        ownerId: 'u1',
        kind: TeamKind.organization,
        members: const {'u1': TeamRole.owner, 'p': TeamRole.player},
        roles: const {
          'a': CustomRole(id: 'a', name: 'Admin'),
          'h': CustomRole(id: 'h', name: 'Handlers', position: 1),
        },
        memberRoles: const {
          'p': {'h'},
        },
        linkedTeams: const {
          'woof': LinkedTeam(id: 'woof', name: 'Woof', roles: {'h'}),
        },
      );
      teams.teams['woof'] = const Team(
        id: 'woof',
        name: 'Woof',
        division: Division.open,
        level: CompetitionLevel.club,
        ownerId: 'u1',
        members: {'u1': TeamRole.owner, 'p': TeamRole.player},
        orgId: 'org',
        orgLinked: true,
        orgMembers: {'p'},
      );
      // An earlier import put everything in the community chat.
      chats.folders['fT'] = const ChatFolder(id: 'fT', name: 'Team');
      chats.teamOf['f:fT'] = 'org';
      // General keeps its place even when named like a room that moves.
      for (final (id, name) in [
        ('old', 'handlers-only'),
        ('gen', 'general'),
        (ChatRoom.generalId, 'Handlers-Only'),
      ]) {
        chats.rooms[id] = ChatRoom(id: id, name: name, folderId: 'fT');
        chats.teamOf['r:$id'] = 'org';
      }

      final vm = DiscordImportViewModel(
        teamId: 'org',
        teamRepository: teams,
        chatRepository: chats,
        discordImportRepository: discord,
        authRepository: FakeAuthRepository(user: testUser),
      );
      addTearDown(vm.dispose);
      await pumpEventQueue();
      vm.setLink('https://discord.new/abc');
      await vm.preview.execute();

      expect(vm.split!.destinations, [null, null, 'woof', null]);
      expect(vm.moving.map((r) => r.id), ['old']);
      expect(vm.emptied, isEmpty);
      final woofImport = vm.teamImports.single;
      expect(woofImport.import.rooms.single.name, 'handlers-only');
      // Handlers is the only role that gets on Woof: the whole team reads it.
      expect(woofImport.import.rooms.single.readRoles, {ChatAudience.everyone});

      await vm.apply.execute();
      expect(vm.apply.error, isFalse);
      expect(vm.done, isTrue);
      final woof = teams.teams['woof']!;
      final copy = woof.roles.values.single;
      expect(copy.name, 'Handlers');
      expect(woof.orgRoles, {copy.id: 'h'});
      // p holds Handlers in the community, so they hold the copy on Woof.
      expect(woof.memberRoles['p'], {copy.id});
      expect(
        chats.roomsOf('woof').map((r) => r.name),
        contains('handlers-only'),
      );
      expect(chats.rooms.containsKey('old'), isFalse);
      expect(
        chats.roomsOf('org').map((r) => r.name),
        isNot(contains('handlers-only')),
      );

      // Sending it back to the community instead is up to the owner.
      vm.setDestination(2, null);
      expect(vm.split!.destinations[2], isNull);
    },
  );

  test(
    'unticked channels never go to a team or move out of the community',
    () async {
      final teams = FakeTeamRepository();
      final chats = FakeChatRepository();
      final discord = FakeDiscordImportRepository(teams, chats);
      teams.teams['org'] = Team(
        id: 'org',
        name: 'Rockets',
        division: Division.mixed,
        level: CompetitionLevel.club,
        ownerId: 'u1',
        kind: TeamKind.organization,
        members: const {'u1': TeamRole.owner},
        roles: const {
          'a': CustomRole(id: 'a', name: 'Admin'),
          'h': CustomRole(id: 'h', name: 'Handlers', position: 1),
        },
        linkedTeams: const {
          'woof': LinkedTeam(id: 'woof', name: 'Woof', roles: {'h'}),
        },
      );
      teams.teams['woof'] = const Team(
        id: 'woof',
        name: 'Woof',
        division: Division.open,
        level: CompetitionLevel.club,
        ownerId: 'u1',
        members: {'u1': TeamRole.owner},
        orgId: 'org',
        orgLinked: true,
      );
      // An earlier import put handlers-only in the community chat.
      chats.folders['fT'] = const ChatFolder(id: 'fT', name: 'Team');
      chats.teamOf['f:fT'] = 'org';
      chats.rooms['old'] = const ChatRoom(
        id: 'old',
        name: 'handlers-only',
        folderId: 'fT',
      );
      chats.teamOf['r:old'] = 'org';

      final vm = DiscordImportViewModel(
        teamId: 'org',
        teamRepository: teams,
        chatRepository: chats,
        discordImportRepository: discord,
        authRepository: FakeAuthRepository(user: testUser),
      );
      addTearDown(vm.dispose);
      await pumpEventQueue();
      vm.setLink('https://discord.new/abc');
      await vm.preview.execute();
      expect(vm.moving.map((r) => r.id), ['old']);

      // A destination set before unticking is kept for when it's ticked
      // again, by the room it was set on.
      vm.setDestination(3, 'woof');
      vm.setPicked(2, false);
      expect(vm.picking!.plan.rooms.map((r) => r.name), [
        'announcements',
        'general',
        'off-topic',
      ]);
      expect(vm.split!.destinations, [null, null, 'woof']);
      expect(vm.moving, isEmpty);
      expect(vm.emptied, isEmpty);
      expect(vm.teamImports.single.import.rooms.map((r) => r.name), [
        'off-topic',
      ]);

      await vm.apply.execute();
      expect(vm.apply.error, isFalse);
      expect(chats.rooms.containsKey('old'), isTrue);
      expect(
        chats.roomsOf('woof').map((r) => r.name),
        isNot(contains('handlers-only')),
      );

      vm.setPicked(2, true);
      expect(vm.split!.destinations, [null, null, 'woof', 'woof']);
    },
  );
}
