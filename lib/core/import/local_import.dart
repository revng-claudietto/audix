import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../database/database.dart';
import '../library/book_finalizer.dart';
import '../storage/file_paths.dart';
import '../subtitle/subtitle_service.dart';

/// Imports an audiobook (an `.m4b` plus optional `.cue`) from device storage:
/// copies the files into the app's per-book folder, then finalizes metadata
/// and chapters via [BookFinalizer].
class LocalImporter {
  LocalImporter(this.db, this.finalizer, this.subtitles);

  final AppDatabase db;
  final BookFinalizer finalizer;
  final SubtitleService subtitles;

  Future<int> importBook({
    required String m4bSourcePath,
    String? cueSourcePath,
    String? subtitleSourcePath,
  }) async {
    final fallbackTitle = p.basenameWithoutExtension(m4bSourcePath);

    // Insert first to obtain the id used for the storage folder name.
    final id = await db.insertBook(
      BooksCompanion.insert(title: fallbackTitle, m4bPath: ''),
    );

    final dir = await FilePaths.ensureBookDir(id);
    await File(m4bSourcePath).copy(p.join(dir.path, 'audio.m4b'));
    if (cueSourcePath != null) {
      await File(cueSourcePath).copy(p.join(dir.path, 'index.cue'));
    }

    await finalizer.finalize(
      id,
      fallbackTitle: fallbackTitle,
      hasCue: cueSourcePath != null,
    );
    if (subtitleSourcePath != null) {
      await subtitles.attach(id, await File(subtitleSourcePath).readAsBytes());
    }
    return id;
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
