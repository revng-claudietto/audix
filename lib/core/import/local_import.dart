import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../database/database.dart';
import '../library/book_finalizer.dart';
import '../storage/storage_locations.dart';
import '../subtitle/subtitle_service.dart';

/// Imports an audiobook (an `.m4b` plus optional `.cue`/subtitle) from device
/// storage. On mobile the files are copied into the audiobook folder and the
/// library scan indexes them; on the web (no filesystem) the bytes are stored
/// in the database.
class LocalImporter {
  LocalImporter(this.db, this.finalizer, this.subtitles);

  final AppDatabase db;
  final BookFinalizer finalizer;
  final SubtitleService subtitles;

  /// Copies an imported book's files into `<root>/<Title>/` and returns that
  /// folder. The caller re-scans afterwards so the scanner creates the book.
  Future<String> importToFolder({
    required String root,
    required String m4bSourcePath,
    String? cueSourcePath,
    String? subtitleSourcePath,
  }) async {
    final title = p.basenameWithoutExtension(m4bSourcePath);
    final dir = Directory(StorageLocations(root).bookDir(title));
    await dir.create(recursive: true);

    await File(m4bSourcePath).copy(p.join(dir.path, StorageLocations.audioName));
    if (cueSourcePath != null) {
      await File(cueSourcePath).copy(p.join(dir.path, StorageLocations.cueName));
    }
    if (subtitleSourcePath != null) {
      await File(subtitleSourcePath)
          .copy(p.join(dir.path, StorageLocations.subtitleName));
    }
    return dir.path;
  }

  /// Imports an audiobook from in-memory bytes (used on the web, where files are
  /// stored in the database rather than on a filesystem).
  Future<int> importBookBytes({
    required String name,
    required Uint8List m4bBytes,
    Uint8List? cueBytes,
    Uint8List? subtitleBytes,
  }) async {
    final fallbackTitle = p.basenameWithoutExtension(name);
    final id = await db.insertBook(
      BooksCompanion.insert(title: fallbackTitle, m4bPath: ''),
    );
    await db.saveBookFile(id, m4bBytes, cueBytes);
    await finalizer.finalizeWeb(
      id,
      fallbackTitle: fallbackTitle,
      m4bBytes: m4bBytes,
      cueBytes: cueBytes,
    );
    if (subtitleBytes != null) await subtitles.attach(id, subtitleBytes);
    return id;
  }
}
