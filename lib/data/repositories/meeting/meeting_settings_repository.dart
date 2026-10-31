import 'dart:convert';

import 'package:logging/logging.dart';

import '../../services/shared_preferences_service.dart';

/// The user's own audio and device choices for meetings. They only affect
/// what this user hears and sends, never the meeting itself.
class MeetingSettings {
  const MeetingSettings({
    this.outputVolume = 1,
    this.participantVolumes = const {},
    this.audioInputId,
    this.audioOutputId,
    this.videoInputId,
    this.micOn = true,
    this.cameraOn = false,
  });

  /// How loud everyone plays, 0–1.
  final double outputVolume;

  /// uid → how loud that person plays relative to [outputVolume], 0–2.
  final Map<String, double> participantVolumes;
  final String? audioInputId;
  final String? audioOutputId;
  final String? videoInputId;

  /// Whether the mic and camera start on when joining.
  final bool micOn;
  final bool cameraOn;

  double volumeOf(String uid) => participantVolumes[uid] ?? 1;

  MeetingSettings copyWith({
    double? outputVolume,
    Map<String, double>? participantVolumes,
    String? Function()? audioInputId,
    String? Function()? audioOutputId,
    String? Function()? videoInputId,
    bool? micOn,
    bool? cameraOn,
  }) => MeetingSettings(
    outputVolume: outputVolume ?? this.outputVolume,
    participantVolumes: participantVolumes ?? this.participantVolumes,
    audioInputId: audioInputId != null ? audioInputId() : this.audioInputId,
    audioOutputId: audioOutputId != null ? audioOutputId() : this.audioOutputId,
    videoInputId: videoInputId != null ? videoInputId() : this.videoInputId,
    micOn: micOn ?? this.micOn,
    cameraOn: cameraOn ?? this.cameraOn,
  );

  factory MeetingSettings.fromJson(Map<String, dynamic> json) {
    double clamp(Object? v, double max, double fallback) =>
        v is num ? v.toDouble().clamp(0, max) : fallback;
    return MeetingSettings(
      outputVolume: clamp(json['outputVolume'], 1, 1),
      participantVolumes: {
        for (final e
            in ((json['participantVolumes'] as Map?) ?? const {}).entries)
          '${e.key}': clamp(e.value, 2, 1),
      },
      audioInputId: json['audioInputId'] as String?,
      audioOutputId: json['audioOutputId'] as String?,
      videoInputId: json['videoInputId'] as String?,
      micOn: json['micOn'] as bool? ?? true,
      cameraOn: json['cameraOn'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'outputVolume': outputVolume,
    'participantVolumes': participantVolumes,
    'audioInputId': audioInputId,
    'audioOutputId': audioOutputId,
    'videoInputId': videoInputId,
    'micOn': micOn,
    'cameraOn': cameraOn,
  };
}

abstract class MeetingSettingsRepository {
  Future<MeetingSettings> load();

  /// Saving is best effort: a failure only means it isn't remembered.
  Future<void> save(MeetingSettings settings);
}

/// [MeetingSettingsRepository] saved on the device.
class MeetingSettingsRepositoryPrefs implements MeetingSettingsRepository {
  MeetingSettingsRepositoryPrefs(this._prefs);

  static const _key = 'meetingSettings';
  static final _log = Logger('MeetingSettings');

  final SharedPreferencesService _prefs;

  @override
  Future<MeetingSettings> load() async {
    try {
      final raw = await _prefs.getString(_key);
      if (raw == null) return const MeetingSettings();
      final json = jsonDecode(raw);
      return json is Map<String, dynamic>
          ? MeetingSettings.fromJson(json)
          : const MeetingSettings();
    } on Exception catch (e) {
      _log.warning('Meeting settings failed to load', e);
      return const MeetingSettings();
    }
  }

  @override
  Future<void> save(MeetingSettings settings) async {
    try {
      await _prefs.setString(_key, jsonEncode(settings.toJson()));
    } on Exception catch (e) {
      _log.warning('Meeting settings failed to save', e);
    }
  }
}
