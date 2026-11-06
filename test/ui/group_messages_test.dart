import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/direct_message/direct_message_repository.dart';
import 'package:frisbee_app/domain/models/app_user.dart';
import 'package:frisbee_app/domain/models/direct_message.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/messages/view_models/direct_chat_viewmodel.dart';
import 'package:frisbee_app/ui/messages/view_models/group_members_viewmodel.dart';
import 'package:frisbee_app/ui/messages/view_models/inbox_viewmodel.dart';
import 'package:frisbee_app/ui/messages/widgets/group_members_screen.dart';
import 'package:frisbee_app/utils/result.dart';

import '../testing/fakes.dart';

void main() {
  late FakeDirectMessageRepository dms;
  late FakeAuthRepository auth;

  const jo = UserProfile(uid: 'jo', name: 'Jo Park');
  const sam = UserProfile(uid: 'sam', name: 'Sam Lee');
  const zed = UserProfile(uid: 'zed', name: 'Zed Cole');

  setUp(() {
    dms = FakeDirectMessageRepository()..profiles.addAll(const [jo, sam, zed]);
    // Jo and Sam follow the user; Zed doesn't.
    dms.follows.addAll({('jo', testUser.uid), ('sam', testUser.uid)});
    auth = FakeAuthRepository(user: testUser);
  });

  GroupMembersViewModel picker({String? groupId}) {
    final vm = GroupMembersViewModel(
      directMessageRepository: dms,
      authRepository: auth,
      groupId: groupId,
    );
    addTearDown(vm.dispose);
    return vm;
  }

  DirectChatViewModel chat(String id, {AppUser? as}) {
    final vm = DirectChatViewModel(
      conversationId: id,
      directMessageRepository: dms,
      authRepository: as == null ? auth : FakeAuthRepository(user: as),
      filePicker: FakeFilePickerService(),
    );
    addTearDown(vm.dispose);
    return vm;
  }

  test('a group is created with the people who follow the user', () async {
    final vm = picker();
    await vm.search.execute('jo');
    expect(vm.results.map((p) => p.uid), ['jo']);
    vm
      ..setName(' Carpool ')
      ..toggle(jo)
      ..toggle(sam)
      ..toggle(zed);
    expect(vm.picked, hasLength(3));
    await vm.save.execute();
    final added = (vm.save.result as Ok<GroupAdded>).value;
    expect(added.notAdded, ['Zed Cole']);
    final g = dms.conversations[added.id]!;
    expect(g.isGroup, isTrue);
    expect(g.name, 'Carpool');
    expect(g.createdBy, testUser.uid);
    expect(g.participants, [testUser.uid, 'jo', 'sam']);
    expect(
      notAddedMessage(added.notAdded),
      startsWith("Zed Cole wasn't added: only people who follow you"),
    );
  });

  test('groups take up to 10 people', () async {
    final vm = picker();
    for (var i = 0; i < 12; i++) {
      final p = UserProfile(uid: 'p$i', name: 'P$i');
      dms.follows.add((p.uid, testUser.uid));
      vm.toggle(p);
    }
    expect(vm.picked, hasLength(Conversation.maxGroupSize - 1));
    expect(vm.room, 0);
  });

  test('the inbox lists a new group straight away, titled by its members '
      'when unnamed', () async {
    final r = await dms.createGroup(testUser, '', const [jo, sam]);
    final inbox = InboxViewModel(
      directMessageRepository: dms,
      authRepository: auth,
    );
    addTearDown(inbox.dispose);
    await pumpEventQueue();
    final item = inbox.allItems.single;
    expect(item.conversation.id, (r as Ok<GroupAdded>).value.id);
    expect(item.title, 'Jo, Sam');
    expect(item.isGroup, isTrue);
    expect(item.preview, 'New group');
  });

  test(
    'members: add, remove (creator only), leave, rename, and "Seen by"',
    () async {
      final id =
          ((await dms.createGroup(testUser, 'Carpool', const [jo]))
                  as Ok<GroupAdded>)
              .value
              .id;
      final mine = chat(id);
      const joUser = AppUser(uid: 'jo', displayName: 'Jo Park');
      final theirs = chat(id, as: joUser);
      await pumpEventQueue();
      expect(mine.isGroup, isTrue);
      expect(mine.title, 'Carpool');
      expect(mine.members.map((m) => m.name), ['You', 'Jo Park']);
      expect(mine.canAddPeople, isTrue);
      expect(mine.canRemove('jo'), isTrue);
      expect(theirs.canRemove(testUser.uid), isFalse);

      // Adding from the chat's Add people screen.
      final add = picker(groupId: id);
      await pumpEventQueue();
      await add.search.execute('jo');
      expect(add.results, isEmpty, reason: 'Jo is already in it');
      add.toggle(sam);
      await add.save.execute();
      await pumpEventQueue();
      expect(mine.members.map((m) => m.uid), [testUser.uid, 'jo', 'sam']);

      // Jo has the chat open, so reads it at once; then Sam does.
      await mine.send.execute('Leaving at 6');
      await pumpEventQueue();
      final last = mine.messages.last;
      expect(mine.receiptFor(last), 'Seen by 1');
      dms.conversations[id] = dms.conversations[id]!.copyWith(
        readAt: {...dms.conversations[id]!.readAt, 'sam': DateTime(2100)},
      );
      dms.emit();
      await pumpEventQueue();
      expect(mine.receiptFor(last), 'Seen by everyone');

      await mine.rename.execute(' Hat league ');
      await pumpEventQueue();
      expect(theirs.title, 'Hat league');

      await mine.removeMember.execute('sam');
      await theirs.leave.execute();
      await pumpEventQueue();
      expect(dms.conversations[id]!.participants, [testUser.uid]);
    },
  );

  testWidgets('the new group screen picks people and names the group', (
    tester,
  ) async {
    final vm = picker();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: GroupMembersScreen(viewModel: vm),
      ),
    );
    expect(find.text('New group'), findsOneWidget);
    expect(
      find.text('You can add people who follow you. 9 more can join.'),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField).last, 'sam');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    await tester.tap(find.text('Sam Lee'));
    await tester.pump();
    expect(find.byType(InputChip), findsOneWidget);
    expect(
      find.text('You can add people who follow you. 8 more can join.'),
      findsOneWidget,
    );
  });
}
