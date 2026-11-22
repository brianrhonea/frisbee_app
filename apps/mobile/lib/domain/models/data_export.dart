import 'dart:convert';
import 'dart:typed_data';

/// "Download your data": the API's JSON file of everything Stall 10 keeps
/// about the user (`GET /v1/me/export`; DataExport in packages/shared),
/// ready to share or save.
class DataExportFile {
  const DataExportFile({required this.name, required this.json});

  /// As the API names it: `stall10-data-YYYY-MM-DD.json` (UTC day).
  static String fileName(DateTime at) =>
      'stall10-data-${at.toUtc().toIso8601String().substring(0, 10)}.json';

  final String name;
  final String json;

  Uint8List get bytes => utf8.encode(json);
}
