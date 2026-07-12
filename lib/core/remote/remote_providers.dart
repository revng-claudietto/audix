import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database.dart';
import '../download/download_service.dart';
import '../providers.dart';
import '../settings/settings_controller.dart';
import '../storage/storage_locations.dart';
import '../storage/storage_permission.dart';
import 'remote_source.dart';

final downloadServiceProvider =
    Provider<DownloadService>((ref) => DownloadService());

/// Lists a server path. Keyed by `(serverId, url)` so navigating folders and
/// refreshing are cheap and cache-friendly.
final remoteListingProvider = FutureProvider.autoDispose
    .family<List<RemoteEntry>, (int, String)>((ref, args) async {
  final (serverId, url) = args;
  final db = ref.read(databaseProvider);
  final server = await db.serverById(serverId);
  if (server == null) return const [];
  final password =
      await ref.read(credentialsStoreProvider).getPassword(serverId);
  final source = createRemoteSource(server, password);
  return source.list(Uri.parse(url));
});

/// Tracks active downloads as `folderKey -> progress` (0..1).
final downloadsProvider =
    NotifierProvider<DownloadsNotifier, Map<String, double>>(
  DownloadsNotifier.new,
);

class DownloadsNotifier extends Notifier<Map<String, double>> {
  @override
  Map<String, double> build() => {};

  /// `folderKey -> background_downloader task id`, so an active download can be
  /// canceled. Kept alongside [state] (which only holds progress).
  final Map<String, String> _taskIds = {};

  bool isDownloading(String key) => state.containsKey(key);

  /// Downloads [folderName]'s files (audio + cue + transcript) into the
  /// audiobook folder, then re-indexes so the scanner creates the book with its
  /// chapters, cover and transcript. Needs all-files access; cleans up a
  /// partial download on failure.
  Future<void> downloadBookAt({
    required Server server,
    required String folderName,
    required String folderKey,
    required RemoteEntry m4b,
    RemoteEntry? cue,
    RemoteEntry? subtitle,
  }) async {
    if (state.containsKey(folderKey)) return;

    if (!await StoragePermission.isGranted()) {
      await StoragePermission.request();
      if (!await StoragePermission.isGranted()) {
        throw const StoragePermissionException();
      }
    }

    state = {...state, folderKey: 0};
    final password =
        await ref.read(credentialsStoreProvider).getPassword(server.id);
    final root = ref.read(settingsProvider).downloadRoot;
    final bookDir = StorageLocations(root).bookDir(folderName);

    try {
      await ref.read(downloadServiceProvider).downloadBook(
            m4b: m4b,
            cue: cue,
            subtitle: subtitle,
            server: server,
            password: password,
            bookDir: bookDir,
            displayName: folderName,
            onTaskId: (taskId) => _taskIds[folderKey] = taskId,
            onProgress: (p) => state = {...state, folderKey: p},
          );
      await ref.read(libraryScannerProvider).scan(root);
    } catch (e) {
      await _deletePartial(bookDir);
      _taskIds.remove(folderKey);
      state = {...state}..remove(folderKey);
      rethrow;
    }
    _taskIds.remove(folderKey);
    state = {...state}..remove(folderKey);
  }

  Future<void> _deletePartial(String bookDir) async {
    try {
      final dir = Directory(bookDir);
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {
      // Best-effort cleanup; a leftover folder is harmless (re-scan ignores
      // folders without an .m4b).
    }
  }

  /// Cancels the in-flight download for [folderKey], if any. The awaiting
  /// [downloadBookAt] then sees a [DownloadCanceledException], deletes the
  /// partial folder, and clears the progress entry.
  Future<void> cancel(String folderKey) async {
    final taskId = _taskIds[folderKey];
    if (taskId != null) await FileDownloader().cancelTaskWithId(taskId);
  }
}
