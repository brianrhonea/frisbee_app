import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../routing/routes.dart';
import '../../../utils/result.dart';
import '../../core/ui/error_message.dart';
import '../view_models/create_team_viewmodel.dart';
import 'team_form.dart';

class CreateTeamScreen extends StatefulWidget {
  const CreateTeamScreen({super.key, required this.viewModel});

  final CreateTeamViewModel viewModel;

  @override
  State<CreateTeamScreen> createState() => _CreateTeamScreenState();
}

class _CreateTeamScreenState extends State<CreateTeamScreen> {
  @override
  void initState() {
    super.initState();
    widget.viewModel.create.addListener(_onResult);
  }

  @override
  void dispose() {
    widget.viewModel.create.removeListener(_onResult);
    super.dispose();
  }

  void _onResult() {
    final cmd = widget.viewModel.create;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New team')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListenableBuilder(
              listenable: widget.viewModel.create,
              builder: (context, _) => TeamForm(
                submitLabel: 'Create team',
                busy: widget.viewModel.create.running,
                onSubmit: widget.viewModel.create.execute,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
