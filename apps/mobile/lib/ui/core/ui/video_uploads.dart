import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../../data/services/feature_flags.dart';

/// Whether native video upload is open, following `meta/flags` live (#13).
/// Rebuilds the caller when the flag changes. Fails closed: false where
/// there are no flags (not signed in, tests) or until they have loaded.
/// Call from `build`.
bool videoUploadsOpen(BuildContext context) {
  try {
    return context.watch<FeatureFlags>().videoUploads;
  } on ProviderNotFoundException {
    return false;
  }
}
