import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'database/database.dart';
import 'import/local_import.dart';
import 'library/book_finalizer.dart';
import 'storage/credentials_store.dart';
import 'subtitle/subtitle_service.dart';

/// Single app-wide drift database instance.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

/// Secure store for server passwords.
final credentialsStoreProvider =
    Provider<CredentialsStore>((ref) => CredentialsStore());

/// Library rows (book + saved position), most recently added first.
final libraryEntriesProvider = StreamProvider<List<LibraryEntry>>(
  (ref) => ref.watch(databaseProvider).watchLibraryEntries(),
);

/// Books with saved progress, most recently played first.
final continueListeningProvider = StreamProvider<List<Book>>(
  (ref) => ref.watch(databaseProvider).watchContinueListening(),
);

/// Configured servers, ordered by name.
final serversProvider = StreamProvider<List<Server>>(
  (ref) => ref.watch(databaseProvider).watchServers(),
);

/// All bookmarks across books, newest first.
final allBookmarksProvider = StreamProvider<List<BookmarkEntry>>(
  (ref) => ref.watch(databaseProvider).watchAllBookmarks(),
);

/// Bookmarks for a specific book, ordered by position.
final bookmarksForProvider =
    StreamProvider.family<List<Bookmark>, int>(
  (ref, bookId) => ref.watch(databaseProvider).watchBookmarks(bookId),
);

final bookFinalizerProvider = Provider<BookFinalizer>(
  (ref) => BookFinalizer(ref.watch(databaseProvider)),
);

/// Parses subtitle/transcript files and stores their cues.
final subtitleServiceProvider = Provider<SubtitleService>(
  (ref) => SubtitleService(ref.watch(databaseProvider)),
);

final localImporterProvider = Provider<LocalImporter>(
  (ref) => LocalImporter(
    ref.watch(databaseProvider),
    ref.watch(bookFinalizerProvider),
    ref.watch(subtitleServiceProvider),
  ),
);
