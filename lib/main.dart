import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/audio/audio_providers.dart';
import 'core/audio/audiobook_handler.dart';
import 'core/download/download_service.dart';
import 'core/settings/settings_controller.dart';
import 'core/storage/file_paths.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FilePaths.init();
  configureDownloadNotifications();
  final prefs = await SharedPreferences.getInstance();
  final handler = await AudiobookHandler.init();

  final settings = AppSettings.fromPrefs(prefs);
  handler.skipInterval = Duration(seconds: settings.skipSeconds);
  handler.smartResume = settings.smartResume;

  runApp(
    ProviderScope(
      overrides: [
        audioHandlerProvider.overrideWithValue(handler),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const AudixApp(),
    ),
  );
}
