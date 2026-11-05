import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/discord/discord_import_repository.dart';
import 'package:frisbee_app/domain/models/chat.dart';
import 'package:frisbee_app/domain/models/discord_import.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/ui/teams/view_models/discord_import_viewmodel.dart';
import 'package:frisbee_app/utils/result.dart';

import '../testing/fakes.dart';

/// What `discord-previewTemplate` returns for
/// functions/test/fixtures/discord_template_synthetic.json (see
/// functions/test/discord/template.test.ts).
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
    }
    for (final r in import.rooms) {
      await chats.saveRoom(team.id, r, uid);
    }
    chats.emit();
    return const Result.ok(null);
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
}
