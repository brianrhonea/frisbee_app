import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../domain/models/data_export.dart';
import '../../../utils/result.dart';
import '../../core/ui/error_message.dart';
import '../../profile/view_models/profile_viewmodel.dart';
import 'settings_widgets.dart';

/// Hands a downloaded data file to the user: the share sheet, which offers
/// Files, Drive, mail and the rest. Tests pass their own.
typedef ShareDataFile =
    Future<void> Function(BuildContext context, DataExportFile file);

/// The share sheet with [file] as a JSON attachment.
Future<void> shareDataFile(BuildContext context, DataExportFile file) async {
  final box = context.findRenderObject() as RenderBox?;
  await SharePlus.instance.share(
    ShareParams(
      files: [
        XFile.fromData(
          file.bytes,
          mimeType: 'application/json',
          name: file.name,
        ),
      ],
      fileNameOverrides: [file.name],
      subject: 'Your Stall 10 data',
      // iPad anchors the sheet here.
      sharePositionOrigin: box == null
          ? null
          : box.localToGlobal(Offset.zero) & box.size,
    ),
  );
}

/// What "Download your data" gives (the website says the same).
const downloadDataDescription =
    'A JSON file of your account, profile, personal details, posts, '
    'comments, messages you sent, follows, people you blocked, reports you '
    'made, teams, RSVPs and stats. '
    'Once every 10 minutes.';

/// Settings › Account › Your data: downloads the user's data
/// ([ProfileViewModel.downloadData]) and shares the file.
class DownloadDataGroup extends StatefulWidget {
  const DownloadDataGroup({
    super.key,
    required this.viewModel,
    this.share = shareDataFile,
  });

  final ProfileViewModel viewModel;
  final ShareDataFile share;

  @override
  State<DownloadDataGroup> createState() => _DownloadDataGroupState();
}

class _DownloadDataGroupState extends State<DownloadDataGroup> {
  @override
  void initState() {
    super.initState();
    widget.viewModel.downloadData.addListener(_onDownload);
  }

  @override
  void dispose() {
    widget.viewModel.downloadData.removeListener(_onDownload);
    super.dispose();
  }

  void _onDownload() {
    final c = widget.viewModel.downloadData;
    if (c.error) {
      showErrorSnackBar(context, c.result);
      c.clearResult();
    } else if (c.result case Ok(:final value)) {
      c.clearResult();
      widget.share(context, value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.viewModel.downloadData;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => SettingsGroup(
        title: 'Your data',
        children: [
          SettingsTile(
            key: const ValueKey('download-data'),
            icon: Icons.download_outlined,
            title: c.running ? 'Preparing your data…' : 'Download your data',
            subtitle: downloadDataDescription,
            opensPage: false,
            onTap: c.running ? null : c.execute,
          ),
        ],
      ),
    );
  }
}
