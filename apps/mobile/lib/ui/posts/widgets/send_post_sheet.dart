import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../domain/models/direct_message.dart';
import '../../../domain/models/user_post.dart';
import '../../../utils/result.dart';
import '../../core/ui/error_message.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/view_model_host.dart';
import '../view_models/send_post_viewmodel.dart';
import '../../core/ui/app_search_field.dart';
import '../../core/ui/skeleton.dart';

/// Sends [post] to people as a direct message, one tap each, or shares its
/// link to another app.
Future<void> showSendPost(BuildContext context, UserPost post) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => ViewModelHost(
        create: (c) => SendPostViewModel(
          post: post,
          directMessageRepository: c.read(),
          authRepository: c.read(),
        ),
        builder: (_, vm) => SendPostSheet(viewModel: vm),
      ),
    );

class SendPostSheet extends StatefulWidget {
  const SendPostSheet({super.key, required this.viewModel});

  final SendPostViewModel viewModel;

  @override
  State<SendPostSheet> createState() => _SendPostSheetState();
}

class _SendPostSheetState extends State<SendPostSheet> {
  final _search = TextEditingController();
  Object? _error;
  bool _copied = false;

  SendPostViewModel get vm => widget.viewModel;

  @override
  void initState() {
    super.initState();
    vm.send.addListener(_onSend);
  }

  @override
  void dispose() {
    vm.send.removeListener(_onSend);
    _search.dispose();
    super.dispose();
  }

  void _onSend() {
    if (vm.send.result case Error(:final error)) {
      setState(() => _error = error);
      vm.send.clearResult();
    }
  }

  Future<void> _share() async {
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        text: vm.messageText,
        // iPad anchors the sheet here.
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: vm.link.toString()));
    if (mounted) setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) {
        final searching = vm.query.length >= SendPostViewModel.minQueryLength;
        final people = searching ? vm.results : vm.recent;
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.75,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Text('Send post', style: theme.textTheme.titleLarge),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: AppSearchField(
                    controller: _search,
                    hint: 'Search people by name',
                    onChanged: vm.search,
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: Text(
                      errorMessage(_error),
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                const SizedBox(height: 8),
                Flexible(
                  child: _PeopleList(
                    viewModel: vm,
                    people: people,
                    searching: searching,
                    onSend: (p) {
                      setState(() => _error = null);
                      vm.send.execute(p);
                    },
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: Wrap(
                    spacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      TextButton.icon(
                        onPressed: _copy,
                        icon: Icon(_copied ? Icons.check : Icons.link),
                        label: Text(_copied ? 'Link copied' : 'Copy link'),
                      ),
                      TextButton.icon(
                        onPressed: _share,
                        icon: const Icon(Icons.ios_share),
                        label: const Text('Share to other apps'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PeopleList extends StatelessWidget {
  const _PeopleList({
    required this.viewModel,
    required this.people,
    required this.searching,
    required this.onSend,
  });

  final SendPostViewModel viewModel;
  final List<UserProfile>? people;
  final bool searching;
  final ValueChanged<UserProfile> onSend;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final list = people;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    Widget note(String text) => Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(color: muted),
      ),
    );
    if (list == null || (searching && vm.searching && list.isEmpty)) {
      return const SkeletonList(count: 4);
    }
    if (list.isEmpty) {
      if (searching && vm.searchError != null) {
        return note(errorMessage(vm.searchError));
      }
      return note(
        searching
            ? 'Nobody found named “${vm.query}”.'
            : 'Search for someone to send this post to.',
      );
    }
    return ListView(
      shrinkWrap: true,
      children: [
        if (!searching)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
            child: Text(
              'Recent',
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: muted),
            ),
          ),
        for (final p in list)
          ListTile(
            leading: PersonAvatar(name: p.name, photoUrl: p.photoUrl),
            title: Text(
              p.name.isEmpty ? 'Stall 10 user' : p.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: p.username == null ? null : Text('@${p.username}'),
            trailing: vm.wasSent(p.uid)
                ? OutlinedButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Sent'),
                  )
                : vm.isSending(p.uid)
                ? const SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : FilledButton(
                    onPressed: () => onSend(p),
                    child: const Text('Send'),
                  ),
          ),
      ],
    );
  }
}
