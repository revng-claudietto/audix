import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../audio/audio_providers.dart';
import '../storage/storage_locations.dart';

/// Persisted, user-configurable playback settings.
class AppSettings {
  const AppSettings({
    this.skipSeconds = 30,
    this.smartResume = true,
    this.downloadRoot = StorageLocations.defaultRoot,
  });

  /// Skip-back/forward amount for the ±buttons.
  final int skipSeconds;

  /// Rewind a few seconds when resuming after a pause.
  final bool smartResume;

  /// Absolute folder where books are stored and re-indexed from.
  final String downloadRoot;

  static const skipKey = 'skip_seconds';
  static const smartResumeKey = 'smart_resume';
  static const downloadRootKey = 'download_root';

  factory AppSettings.fromPrefs(SharedPreferences prefs) => AppSettings(
        skipSeconds: prefs.getInt(skipKey) ?? 30,
        smartResume: prefs.getBool(smartResumeKey) ?? true,
        downloadRoot:
            prefs.getString(downloadRootKey) ?? StorageLocations.defaultRoot,
      );

  AppSettings copyWith({
    int? skipSeconds,
    bool? smartResume,
    String? downloadRoot,
  }) =>
      AppSettings(
        skipSeconds: skipSeconds ?? this.skipSeconds,
        smartResume: smartResume ?? this.smartResume,
        downloadRoot: downloadRoot ?? this.downloadRoot,
      );
}

/// The loaded SharedPreferences instance. Overridden in `main()`.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError(
    'sharedPreferencesProvider must be overridden in main()',
  ),
);

final settingsProvider =
    NotifierProvider<SettingsController, AppSettings>(SettingsController.new);

class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() =>
      AppSettings.fromPrefs(ref.watch(sharedPreferencesProvider));

  Future<void> setSkipSeconds(int seconds) async {
    await ref
        .read(sharedPreferencesProvider)
        .setInt(AppSettings.skipKey, seconds);
    state = state.copyWith(skipSeconds: seconds);
    ref.read(audioHandlerProvider).skipInterval = Duration(seconds: seconds);
  }

  Future<void> setSmartResume(bool value) async {
    await ref
        .read(sharedPreferencesProvider)
        .setBool(AppSettings.smartResumeKey, value);
    state = state.copyWith(smartResume: value);
    ref.read(audioHandlerProvider).smartResume = value;
  }

  Future<void> setDownloadRoot(String path) async {
    final normalized = path.trim();
    if (normalized.isEmpty) return;
    await ref
        .read(sharedPreferencesProvider)
        .setString(AppSettings.downloadRootKey, normalized);
    state = state.copyWith(downloadRoot: normalized);
  }
}
