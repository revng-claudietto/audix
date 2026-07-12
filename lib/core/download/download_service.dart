import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../database/database.dart';
import '../remote/remote_source.dart';
import '../storage/storage_locations.dart';

/// Thrown by [DownloadService.downloadBook] when the user cancels the transfer
/// (so callers can tell a cancellation apart from a genuine failure).
class DownloadCanceledException implements Exception {
  const DownloadCanceledException();

  @override
  String toString() => 'Download canceled';
}

/// Configures the system notification background_downloader posts for running
/// downloads. On Android this is also the foreground-service notification that
/// keeps the transfer alive while the app is in the background, and it carries
/// the native pause/cancel buttons. Call once at startup. No-op on web, which
/// has no background service.
void configureDownloadNotifications() {
  if (kIsWeb) return;
  FileDownloader().configureNotification(
    running: const TaskNotification('Downloading', '{displayName}'),
    complete: const TaskNotification('Downloaded', '{displayName}'),
    error: const TaskNotification('Download failed', '{displayName}'),
    paused: const TaskNotification('Download paused', '{displayName}'),
    progressBar: true,
  );
}

/// Downloads a book's files into its folder on disk: the `.m4b` plus any
/// secondary files (a `.cue` for chapters, a `.vtt`/`.srt` transcript). The
/// library scan then indexes the folder, so downloaded books flow through the
/// exact same path as ones dropped into the folder by hand.
class DownloadService {
  Future<void> downloadBook({
    required RemoteEntry m4b,
    RemoteEntry? cue,
    RemoteEntry? subtitle,
    required Server server,
    required String? password,
    required String bookDir,
    required String displayName,
    void Function(String taskId)? onTaskId,
    void Function(double progress)? onProgress,
  }) async {
    // On Android 13+ the progress / foreground-service notification needs the
    // POST_NOTIFICATIONS permission; ask once, the first time it's needed.
    if (!kIsWeb) {
      final permissions = FileDownloader().permissions;
      if (await permissions.status(PermissionType.notifications) ==
          PermissionStatus.undetermined) {
        await permissions.request(PermissionType.notifications);
      }
    }

    final headers = <String, String>{};
    if (server.username.isNotEmpty) {
      headers['Authorization'] =
          basicAuthHeader(server.username, password ?? '');
    }
    // BaseDirectory.root treats `directory` as relative to the filesystem root,
    // so strip the leading slash of the absolute book folder.
    final directory =
        bookDir.startsWith('/') ? bookDir.substring(1) : bookDir;

    DownloadTask task(String url, String filename) => DownloadTask(
          url: url,
          filename: filename,
          directory: directory,
          baseDirectory: BaseDirectory.root,
          headers: headers,
          displayName: displayName,
        );

    final m4bTask = DownloadTask(
      url: m4b.url.toString(),
      filename: StorageLocations.audioName,
      directory: directory,
      baseDirectory: BaseDirectory.root,
      headers: headers,
      displayName: displayName,
      updates: Updates.statusAndProgress,
      allowPause: true,
    );
    // Hand the task id back so the download can be canceled while in flight.
    onTaskId?.call(m4bTask.taskId);
    final result = await FileDownloader().download(
      m4bTask,
      onProgress: (progress) {
        if (progress >= 0) onProgress?.call(progress);
      },
    );
    if (result.status == TaskStatus.canceled) {
      throw const DownloadCanceledException();
    }
    if (result.status != TaskStatus.complete) {
      throw Exception('Audio download ${result.status.name}');
    }

    // Secondary files: fetch after the audio so a cancel mid-audio skips them.
    if (cue != null) {
      await FileDownloader().download(task(cue.url.toString(),
          StorageLocations.cueName));
    }
    if (subtitle != null) {
      // Saved under a .vtt name; the parser autodetects VTT vs SRT by content.
      await FileDownloader().download(task(subtitle.url.toString(),
          StorageLocations.subtitleName));
    }
  }
}
