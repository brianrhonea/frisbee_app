import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../routing/routes.dart';
import '../../../utils/result.dart';
import '../../core/themes/theme.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/layout.dart' show PersonAvatar;
import '../../core/ui/status_views.dart';
import '../view_models/people_search_viewmodel.dart';

/// Search the directory by name and start a conversation.
class PeopleSearchScreen extends StatefulWidget {
  const PeopleSearchScreen({super.key, required this.viewModel});

  final PeopleSearchViewModel viewModel;

  @override
  State<PeopleSearchScreen> createState() => _PeopleSearchScreenState();
}

class _PeopleSearchScreenState extends State<PeopleSearchScreen> {
  PeopleSearchViewModel get vm => widget.viewModel;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    vm.open.addListener(_onOpen);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    vm.open.removeListener(_onOpen);
    super.dispose();
  }

  void _onOpen() {
    switch (vm.open.result) {
      case Ok(:final value):
        vm.open.clearResult();
        context.pushReplacement(Routes.conversation(value));
      case final Error<String> e:
        showErrorSnackBar(context, e);
        vm.open.clearResult();
      case null:
        break;
    }
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => vm.search.execute(text),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('New message')),
      body: ConstrainedContent(
        maxWidth: 720,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search people by name',
                ),
                onChanged: _onChanged,
                onSubmitted: vm.search.execute,
              ),
            ),
            Expanded(
              child: ListenableBuilder(
                listenable: Listenable.merge([vm.search, vm.open]),
                builder: (context, _) {
                  if (vm.search.running) return const LoadingView();
                  if (vm.search.error) {
                    return ErrorView(error: vm.search.result);
                  }
                  if (vm.noMatches) {
                    return const EmptyView(
                      icon: Icons.person_search_outlined,
                      title: 'No one found',
                      message:
                          'Try their first or last name. People show up once '
                          "they've set a name in their profile.",
                    );
                  }
                  final results = vm.results;
                  if (results.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Type at least ${PeopleSearchViewModel.minQueryLength}'
                        ' letters of a name.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: c.muted),
                      ),
                    );
                  }
                  return ListView.builder(
                    itemCount: results.length,
                    itemBuilder: (context, i) {
                      final p = results[i];
                      return ListTile(
                        enabled: !vm.open.running,
                        leading: PersonAvatar(
                          name: p.name,
                          photoUrl: p.photoUrl,
                        ),
                        title: Text(p.name),
                        trailing: const Icon(Icons.chat_bubble_outline),
                        onTap: () => vm.open.execute(p),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
