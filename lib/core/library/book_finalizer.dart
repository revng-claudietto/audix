import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';

import '../cue/cue_parser.dart';
import '../database/database.dart';
import '../storage/blob_url_stub.dart'
    if (dart.library.js_interop) '../storage/blob_url_web.dart';
import '../storage/file_paths.dart';
import 'cover_extractor.dart';

/// Completes a book after its files are in place (imported, downloaded, or
/// discovered by the library scan): probes the duration, extracts an embedded
/// cover, parses the cue (or falls back to a single chapter), and writes
/// metadata + chapters to the database.
///
/// Filesystem books keep their audio/cue as ABSOLUTE paths (the scan refreshes
/// them each launch); covers are cached app-privately under `audiobooks/<id>/`.
class BookFinalizer {
  BookFinalizer(this.db);

  final AppDatabase db;

  /// Finalizes a filesystem book whose files already sit in its folder.
  /// [m4bAbsolute]/[cueAbsolute] are absolute paths; [title] is the folder name
  /// (what the user sees on disk), so it wins over any cue-embedded title.
  Future<void> finalizeFolderBook(
    int id, {
    required String title,
    required String m4bAbsolute,
    String? cueAbsolute,
  }) async {
    final durationMs = await probeDurationMs(m4bAbsolute);

    CueSheet? sheet;
    if (cueAbsolute != null) {
      final cueFile = File(cueAbsolute);
      if (await cueFile.exists()) {
        sheet = CueParser.parse(await cueFile.readAsString());
      } else {
        cueAbsolute = null;
      }
    }

    final coverRelative = await _extractCover(id, m4bAbsolute);

    final chapters = sheet != null
        ? chaptersFromCue(sheet, durationMs: durationMs)
        : singleChapter(durationMs: durationMs, title: title);

    await db.finalizeImportedBook(
      id,
      m4bPath: m4bAbsolute,
      cuePath: cueAbsolute,
      coverPath: coverRelative,
      author: sheet?.performer,
      title: title,
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

  /// Web finalize: the file bytes are already stored in the database (there is
  /// no filesystem). Probes the duration from an object URL, parses the cue from
  /// bytes, and writes metadata + chapters. Covers are skipped on the web.
  Future<void> finalizeWeb(
    int id, {
    required String fallbackTitle,
    String? author,
    required Uint8List m4bBytes,
    Uint8List? cueBytes,
  }) async {
    final url = objectUrlFromBytes(m4bBytes, 'audio/mp4');
    int durationMs;
    try {
      durationMs = await _probeDurationUriMs(url);
    } finally {
      revokeObjectUrl(url);
    }

    final sheet =
        cueBytes != null ? CueParser.parse(utf8.decode(cueBytes, allowMalformed: true)) : null;
    final chapters = sheet != null
        ? chaptersFromCue(sheet, durationMs: durationMs)
        : singleChapter(durationMs: durationMs, title: fallbackTitle);

    await db.finalizeImportedBook(
      id,
      m4bPath: FilePaths.relativePath(id, 'audio.m4b'),
      cuePath: cueBytes != null ? FilePaths.relativePath(id, 'index.cue') : null,
      coverPath: null,
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

  Future<int> _probeDurationUriMs(String url) async {
    final player = AudioPlayer();
    try {
      final duration =
          await player.setAudioSource(AudioSource.uri(Uri.parse(url)));
      return duration?.inMilliseconds ?? 0;
    } catch (_) {
      return 0;
    } finally {
      await player.dispose();
    }
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
    // Covers are cached app-privately (not in the user's audiobook folder), so
    // ensure that per-book directory exists before writing into it.
    await FilePaths.ensureBookDir(id);
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
