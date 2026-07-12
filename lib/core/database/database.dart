import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'database.g.dart';

/// How a server exposes its audiobook folders. Stored as the enum index.
enum ServerType { autoindex, webdav, json }

/// How a bookmark was created. Stored as the enum index.
///
/// [manual] bookmarks are added explicitly by the user; [autoStart] /
/// [autoStop] are created automatically when playback starts / stops.
enum BookmarkKind { manual, autoStart, autoStop }

@DataClassName('Server')
class Servers extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get baseUrl => text()();
  TextColumn get username => text().withDefault(const Constant(''))();
  IntColumn get type => intEnum<ServerType>().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('Book')
class Books extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Source server, or null for a book imported from the device / detached.
  IntColumn get serverId => integer().nullable()();
  TextColumn get title => text()();
  TextColumn get author => text().nullable()();

  /// Paths are RELATIVE to the app documents directory (see FilePaths).
  TextColumn get m4bPath => text()();
  TextColumn get cuePath => text().nullable()();
  IntColumn get durationMs => integer().withDefault(const Constant(0))();
  TextColumn get coverPath => text().nullable()();
  BoolColumn get completed => boolean().withDefault(const Constant(false))();
  DateTimeColumn get addedAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('Chapter')
class Chapters extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get bookId =>
      integer().references(Books, #id, onDelete: KeyAction.cascade)();
  IntColumn get chapterIndex => integer()();
  TextColumn get title => text()();
  IntColumn get startMs => integer()();
  IntColumn get endMs => integer()();
}

@DataClassName('PlaybackProgress')
class Playback extends Table {
  IntColumn get bookId =>
      integer().references(Books, #id, onDelete: KeyAction.cascade)();
  IntColumn get positionMs => integer().withDefault(const Constant(0))();
  IntColumn get currentChapter => integer().withDefault(const Constant(0))();
  RealColumn get speed => real().withDefault(const Constant(1.0))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {bookId};
}

@DataClassName('Bookmark')
class Bookmarks extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get bookId =>
      integer().references(Books, #id, onDelete: KeyAction.cascade)();
  IntColumn get positionMs => integer()();
  IntColumn get chapterIndex => integer().withDefault(const Constant(0))();
  TextColumn get note => text().nullable()();

  /// Whether this was added manually or automatically on play/pause.
  IntColumn get kind => intEnum<BookmarkKind>().withDefault(const Constant(0))();

  /// Wall-clock time the bookmark was introduced.
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Audiobook file bytes, stored in the database on the web (where there is no
/// filesystem). On mobile the files live on disk and this table is unused.
@DataClassName('BookFile')
class BookFiles extends Table {
  IntColumn get bookId =>
      integer().references(Books, #id, onDelete: KeyAction.cascade)();
  BlobColumn get m4b => blob()();
  BlobColumn get cue => blob().nullable()();

  @override
  Set<Column> get primaryKey => {bookId};
}

/// A book's transcript: one timed line per row, parsed from a `.vtt`/`.srt`.
/// Named `SubtitleCueRow` to avoid clashing with the parser's `SubtitleCue`.
@DataClassName('SubtitleCueRow')
class SubtitleCues extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get bookId =>
      integer().references(Books, #id, onDelete: KeyAction.cascade)();
  IntColumn get cueIndex => integer()();
  IntColumn get startMs => integer()();
  IntColumn get endMs => integer()();
  // Named `content` rather than `text` so it doesn't shadow Table.text().
  TextColumn get content => text()();
}

@DriftDatabase(
    tables: [Servers, Books, Chapters, Playback, Bookmarks, BookFiles, SubtitleCues])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
      : super(executor ??
            driftDatabase(
              name: 'audix',
              // Required when running on the web: drift loads sqlite3 as wasm
              // and runs in a worker, both served from the web root (see web/).
              web: DriftWebOptions(
                sqlite3Wasm: Uri.parse('sqlite3.wasm'),
                driftWorker: Uri.parse('drift_worker.js'),
              ),
            ));

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          if (from < 2) await m.createTable(bookmarks);
          if (from < 3) await m.addColumn(bookmarks, bookmarks.kind);
          if (from < 4) await m.createTable(bookFiles);
          if (from < 5) await m.createTable(subtitleCues);
        },
        beforeOpen: (details) async {
          // Required so KeyAction.cascade foreign keys are enforced.
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  // ---------------------------------------------------------------- Servers
  Stream<List<Server>> watchServers() =>
      (select(servers)..orderBy([(s) => OrderingTerm(expression: s.name)]))
          .watch();

  Future<List<Server>> allServers() => select(servers).get();

  Future<Server?> serverById(int id) =>
      (select(servers)..where((s) => s.id.equals(id))).getSingleOrNull();

  Future<int> insertServer(ServersCompanion server) =>
      into(servers).insert(server);

  Future<bool> updateServer(Server server) => update(servers).replace(server);

  /// Removes a server. Downloaded books are kept (their [serverId] is cleared)
  /// so they remain available in the local library.
  Future<void> deleteServer(int id) async {
    await (update(books)..where((b) => b.serverId.equals(id)))
        .write(const BooksCompanion(serverId: Value(null)));
    await (delete(servers)..where((s) => s.id.equals(id))).go();
  }

  // ------------------------------------------------------------------ Books
  Stream<List<Book>> watchBooks() =>
      (select(books)..orderBy([(b) => OrderingTerm.desc(b.addedAt)])).watch();

  Future<Book?> bookById(int id) =>
      (select(books)..where((b) => b.id.equals(id))).getSingleOrNull();

  Future<int> insertBook(BooksCompanion book) => into(books).insert(book);

  Future<bool> updateBook(Book book) => update(books).replace(book);

  Future<void> deleteBook(int id) =>
      (delete(books)..where((b) => b.id.equals(id))).go();

  // ----------------------------------------------------------- Book files (web)
  Future<void> saveBookFile(int bookId, Uint8List m4b, Uint8List? cue) =>
      into(bookFiles).insertOnConflictUpdate(BookFilesCompanion.insert(
        bookId: Value(bookId),
        m4b: m4b,
        cue: cue == null ? const Value.absent() : Value(cue),
      ));

  Future<BookFile?> bookFile(int bookId) =>
      (select(bookFiles)..where((f) => f.bookId.equals(bookId)))
          .getSingleOrNull();

  /// Books that have a saved position, most-recently-played first.
  Stream<List<Book>> watchContinueListening() {
    final query = select(books).join(
      [innerJoin(playback, playback.bookId.equalsExp(books.id))],
    )
      ..where(books.completed.equals(false))
      ..orderBy([OrderingTerm.desc(playback.updatedAt)]);
    return query
        .watch()
        .map((rows) => rows.map((r) => r.readTable(books)).toList());
  }

  /// All books joined with their saved position (left join), newest first.
  Stream<List<LibraryEntry>> watchLibraryEntries() {
    final query = select(books).join(
      [leftOuterJoin(playback, playback.bookId.equalsExp(books.id))],
    )..orderBy([OrderingTerm.desc(books.addedAt)]);
    return query.watch().map(
          (rows) => rows.map((r) {
            final progress = r.readTableOrNull(playback);
            return LibraryEntry(
              book: r.readTable(books),
              positionMs: progress?.positionMs ?? 0,
              updatedAt: progress?.updatedAt,
            );
          }).toList(),
        );
  }

  // --------------------------------------------------------------- Chapters
  Future<void> insertChapters(List<ChaptersCompanion> rows) =>
      batch((b) => b.insertAll(chapters, rows));

  Future<List<Chapter>> chaptersFor(int bookId) => (select(chapters)
        ..where((c) => c.bookId.equals(bookId))
        ..orderBy([(c) => OrderingTerm(expression: c.chapterIndex)]))
      .get();

  // -------------------------------------------------------------- Subtitles
  /// A book's transcript lines, in order, updating live as they change.
  Stream<List<SubtitleCueRow>> watchSubtitles(int bookId) =>
      (select(subtitleCues)
            ..where((s) => s.bookId.equals(bookId))
            ..orderBy([(s) => OrderingTerm(expression: s.cueIndex)]))
          .watch();

  /// Live count of a book's transcript lines. Cheap enough to watch from the
  /// player just to decide whether to offer the transcript view, without
  /// loading a (potentially book-length) transcript into memory.
  Stream<int> watchSubtitleCount(int bookId) {
    final count = subtitleCues.id.count();
    return (selectOnly(subtitleCues)
          ..addColumns([count])
          ..where(subtitleCues.bookId.equals(bookId)))
        .watchSingle()
        .map((row) => row.read(count) ?? 0);
  }

  /// Replaces a book's transcript with [rows] (removing any existing lines).
  Future<void> replaceSubtitles(
      int bookId, List<SubtitleCuesCompanion> rows) async {
    await (delete(subtitleCues)..where((s) => s.bookId.equals(bookId))).go();
    if (rows.isNotEmpty) await batch((b) => b.insertAll(subtitleCues, rows));
  }

  // --------------------------------------------------------------- Playback
  Future<PlaybackProgress?> playbackFor(int bookId) =>
      (select(playback)..where((p) => p.bookId.equals(bookId)))
          .getSingleOrNull();

  Future<void> savePosition(
    int bookId, {
    required int positionMs,
    required int chapterIndex,
    double? speed,
    bool? completed,
  }) async {
    await into(playback).insertOnConflictUpdate(
      PlaybackCompanion.insert(
        bookId: Value(bookId),
        positionMs: Value(positionMs),
        currentChapter: Value(chapterIndex),
        speed: speed == null ? const Value.absent() : Value(speed),
        updatedAt: Value(DateTime.now()),
      ),
    );
    if (completed != null) {
      await (update(books)..where((b) => b.id.equals(bookId)))
          .write(BooksCompanion(completed: Value(completed)));
    }
  }

  /// Fills in a book's file paths, metadata, and duration after import/download.
  Future<void> finalizeImportedBook(
    int id, {
    required String m4bPath,
    String? cuePath,
    String? coverPath,
    String? author,
    required String title,
    required int durationMs,
  }) {
    return (update(books)..where((b) => b.id.equals(id))).write(BooksCompanion(
      m4bPath: Value(m4bPath),
      cuePath: Value(cuePath),
      coverPath: Value(coverPath),
      author: Value(author),
      title: Value(title),
      durationMs: Value(durationMs),
    ));
  }

  /// Books that have no cover image yet (for backfill).
  Future<List<Book>> booksWithoutCover() =>
      (select(books)..where((b) => b.coverPath.isNull())).get();

  /// Sets only the cover path for a book.
  Future<void> setBookCover(int id, String coverPath) =>
      (update(books)..where((b) => b.id.equals(id)))
          .write(BooksCompanion(coverPath: Value(coverPath)));

  // -------------------------------------------------------------- Bookmarks
  Stream<List<Bookmark>> watchBookmarks(int bookId) => (select(bookmarks)
        ..where((b) => b.bookId.equals(bookId))
        ..orderBy([(b) => OrderingTerm(expression: b.positionMs)]))
      .watch();

  Future<int> addBookmark(BookmarksCompanion bookmark) =>
      into(bookmarks).insert(bookmark);

  Future<void> updateBookmarkNote(int id, String? note) =>
      (update(bookmarks)..where((b) => b.id.equals(id)))
          .write(BookmarksCompanion(note: Value(note)));

  Future<void> deleteBookmark(int id) =>
      (delete(bookmarks)..where((b) => b.id.equals(id))).go();

  /// Removes all automatic (start/stop) bookmarks for a book, keeping manual ones.
  Future<void> clearAutoBookmarks(int bookId) =>
      (delete(bookmarks)
            ..where((b) =>
                b.bookId.equals(bookId) &
                b.kind.equals(BookmarkKind.manual.index).not()))
          .go();

  /// All bookmarks across books (newest first), each with its book.
  Stream<List<BookmarkEntry>> watchAllBookmarks() {
    final query = select(bookmarks).join(
      [innerJoin(books, books.id.equalsExp(bookmarks.bookId))],
    )..orderBy([OrderingTerm.desc(bookmarks.createdAt)]);
    return query.watch().map(
          (rows) => rows
              .map((r) => BookmarkEntry(
                    bookmark: r.readTable(bookmarks),
                    book: r.readTable(books),
                  ))
              .toList(),
        );
  }
}

/// A library row: a book plus its saved playback position (if any).
class LibraryEntry {
  const LibraryEntry({
    required this.book,
    required this.positionMs,
    this.updatedAt,
  });

  final Book book;
  final int positionMs;
  final DateTime? updatedAt;
}

/// A bookmark together with the book it belongs to (for the global list).
class BookmarkEntry {
  const BookmarkEntry({required this.bookmark, required this.book});

  final Bookmark bookmark;
  final Book book;
}
