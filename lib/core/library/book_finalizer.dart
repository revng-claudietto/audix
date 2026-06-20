import 'dart:io';

import 'package:just_audio/just_audio.dart';

import '../cue/cue_parser.dart';
import '../database/database.dart';
import '../storage/file_paths.dart';
import 'cover_extractor.dart';

/// Completes a book after its files are in place (imported or downloaded):
/// probes the duration, extracts an embedded cover, parses the cue (or falls
/// back to a single chapter), and writes metadata + chapters to the database.
///
/// Expects the files at `audiobooks/<id>/audio.m4b` (+ optional `index.cue`).
class BookFinalizer {
  BookFinalizer(this.db);

  final AppDatabase db;

  Future<void> finalize(
    int id, {
    required String fallbackTitle,
    String? author,
    required bool hasCue,
  }) async {
    final m4bRelative = FilePaths.relativePath(id, 'audio.m4b');
    final m4bAbsolute = await FilePaths.absolutePath(m4bRelative);
    final durationMs = await probeDurationMs(m4bAbsolute);

    CueSheet? sheet;
    String? cueRelative;
    if (hasCue) {
      cueRelative = FilePaths.relativePath(id, 'index.cue');
      final cueFile = File(await FilePaths.absolutePath(cueRelative));
      if (await cueFile.exists()) {
        sheet = CueParser.parse(await cueFile.readAsString());
      } else {
        cueRelative = null;
      }
    }

    final coverRelative = await _extractCover(id, m4bAbsolute);

    final chapters = sheet != null
        ? chaptersFromCue(sheet, durationMs: durationMs)
        : singleChapter(durationMs: durationMs, title: fallbackTitle);

    await db.finalizeImportedBook(
      id,
      m4bPath: m4bRelative,
      cuePath: cueRelative,
      coverPath: coverRelative,
      author: author ?? sheet?.performer,
      title: sheet?.title ?? fallbackTitle,
      durationMs: durationMs,
    );

    await db.insertChapters([
      for (final c in chapters)
        ChaptersCompanion.insert(
          bookId: id,
          chapterIndex: c.index,
          title: c.title,
          startMs: c.startMs,
          endMs: c.endMs,
        ),
    ]);
  }

  /// Extracts and stores covers for any books that still lack one.
  /// Returns the number of covers added.
  Future<int> backfillCovers() async {
    final books = await db.booksWithoutCover();
    var added = 0;
    for (final book in books) {
      if (book.m4bPath.isEmpty) continue;
      final absolute = await FilePaths.absolutePath(book.m4bPath);
      final relative = await _extractCover(book.id, absolute);
      if (relative != null) {
        await db.setBookCover(book.id, relative);
        added++;
      }
    }
    return added;
  }

  Future<String?> _extractCover(int id, String m4bAbsolute) async {
    final bytes = await CoverExtractor.extract(m4bAbsolute);
    if (bytes == null || bytes.isEmpty) return null;
    final relative = FilePaths.relativePath(id, 'cover.jpg');
    await File(await FilePaths.absolutePath(relative)).writeAsBytes(bytes);
    return relative;
  }

  Future<int> probeDurationMs(String absolutePath) async {
    final player = AudioPlayer();
    try {
      final duration =
          await player.setAudioSource(AudioSource.file(absolutePath));
      return duration?.inMilliseconds ?? 0;
    } catch (_) {
      return 0;
    } finally {
      await player.dispose();
    }
  }
}
