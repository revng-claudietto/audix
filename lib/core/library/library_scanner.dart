import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;

import '../database/database.dart';
import '../storage/fingerprint.dart';
import '../storage/storage_permission.dart';
import '../subtitle/subtitle_service.dart';
import 'book_finalizer.dart';

/// Re-indexes the audiobooks folder into the database. The folder is the source
/// of truth for *which* books exist and where; the database holds the derived
/// metadata (chapters, cover) and the app-owned state (position, bookmarks,
/// subtitles), keyed to each book's audio fingerprint so it survives renames
/// and moves. Runs at startup and on demand.
class LibraryScanner {
  LibraryScanner(this.db, this.finalizer, this.subtitles);

  final AppDatabase db;
  final BookFinalizer finalizer;
  final SubtitleService subtitles;

  bool _running = false;

  /// Reconciles the books under [root] with the database. No-op on web, without
  /// all-files access, or if the folder doesn't exist yet.
  Future<void> scan(String root) async {
    if (kIsWeb || _running) return;
    _running = true;
    try {
      if (!await StoragePermission.isGranted()) return;
      final dir = Directory(root);
      if (!await dir.exists()) return;

      final existing = {
        for (final b in await db.filesystemBooks()) b.fingerprint!: b,
      };
      final seen = <String>{};

      await for (final entry in dir.list(followLinks: false)) {
        if (entry is! Directory) continue;
        final found = await _filesIn(entry);
        final m4b = found.m4b;
        if (m4b == null) continue;

        final fingerprint = await FileFingerprint.of(m4b);
        if (fingerprint == null || !seen.add(fingerprint)) continue;

        final title = p.basename(entry.path);
        final book = existing[fingerprint];
        if (book == null) {
          await _addBook(fingerprint, title, found);
        } else {
          await _refreshBook(book, title, found);
        }
      }

      // Books whose audio is no longer on disk drop out of the library
      // (cascades their chapters/playback/bookmarks/subtitles).
      for (final entry in existing.entries) {
        if (!seen.contains(entry.key)) await db.deleteBook(entry.value.id);
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _addBook(
      String fingerprint, String title, _BookFiles found) async {
    final id = await db.insertBook(BooksCompanion.insert(
      title: title,
      m4bPath: found.m4b!.path,
      fingerprint: Value(fingerprint),
    ));
    await finalizer.finalizeFolderBook(
      id,
      title: title,
      m4bAbsolute: found.m4b!.path,
      cueAbsolute: found.cue?.path,
    );
    if (found.subtitle != null) {
      await subtitles.attach(id, await found.subtitle!.readAsBytes());
    }
  }

  Future<void> _refreshBook(Book book, String title, _BookFiles found) async {
    if (book.title != title ||
        book.m4bPath != found.m4b!.path ||
        book.cuePath != found.cue?.path) {
      await db.updateBookLocation(
        book.id,
        title: title,
        m4bPath: found.m4b!.path,
        cuePath: found.cue?.path,
      );
    }
    // Pick up a transcript that was added to the folder after the book existed.
    if (found.subtitle != null && await db.subtitleCount(book.id) == 0) {
      await subtitles.attach(book.id, await found.subtitle!.readAsBytes());
    }
  }

  Future<_BookFiles> _filesIn(Directory dir) async {
    File? m4b, cue, subtitle;
    await for (final f in dir.list(followLinks: false)) {
      if (f is! File) continue;
      final lower = f.path.toLowerCase();
      if (lower.endsWith('.m4b')) {
        m4b ??= f;
      } else if (lower.endsWith('.cue')) {
        cue ??= f;
      } else if (lower.endsWith('.vtt') || lower.endsWith('.srt')) {
        subtitle ??= f;
      }
    }
    return _BookFiles(m4b: m4b, cue: cue, subtitle: subtitle);
  }
}

/// The recognised files inside one book folder.
class _BookFiles {
  const _BookFiles({this.m4b, this.cue, this.subtitle});

  final File? m4b;
  final File? cue;
  final File? subtitle;
}
