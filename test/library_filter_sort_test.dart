import 'package:flutter_test/flutter_test.dart';

import 'package:audix/core/database/database.dart';
import 'package:audix/features/library/library_screen.dart';

Book _book({
  required int id,
  String title = 'Title',
  String? author,
  DateTime? addedAt,
}) =>
    Book(
      id: id,
      serverId: null,
      title: title,
      author: author,
      m4bPath: 'audiobooks/$id/audio.m4b',
      cuePath: null,
      durationMs: 1000,
      coverPath: null,
      completed: false,
      addedAt: addedAt ?? DateTime(2020),
    );

LibraryEntry _entry({
  required int id,
  String title = 'Title',
  String? author,
  int positionMs = 0,
  DateTime? updatedAt,
  DateTime? addedAt,
}) =>
    LibraryEntry(
      book: _book(id: id, title: title, author: author, addedAt: addedAt),
      positionMs: positionMs,
      updatedAt: updatedAt,
    );

void main() {
  final entries = [
    _entry(
        id: 1,
        title: 'Animal Farm',
        author: 'Orwell',
        addedAt: DateTime(2021),
        updatedAt: DateTime(2023, 1, 1)),
    _entry(id: 2, title: 'Brave New World', author: 'Huxley', addedAt: DateTime(2022)),
    _entry(
        id: 3,
        title: '1984',
        author: 'Orwell',
        addedAt: DateTime(2020),
        updatedAt: DateTime(2023, 5, 1)),
  ];

  test('filterLibrary matches title and author, case-insensitive', () {
    expect(filterLibrary(entries, 'orwell').map((e) => e.book.id), [1, 3]);
    expect(filterLibrary(entries, '1984').map((e) => e.book.id), [3]);
    expect(filterLibrary(entries, 'BRAVE').map((e) => e.book.id), [2]);
    expect(filterLibrary(entries, '').length, 3);
    expect(filterLibrary(entries, 'zzz'), isEmpty);
  });

  test('sortLibrary by title', () {
    expect(
      sortLibrary(entries, LibrarySort.title).map((e) => e.book.title),
      ['1984', 'Animal Farm', 'Brave New World'],
    );
  });

  test('sortLibrary by recently added (newest first)', () {
    expect(
      sortLibrary(entries, LibrarySort.recentlyAdded).map((e) => e.book.id),
      [2, 1, 3],
    );
  });

  test('sortLibrary by recently played puts never-played last', () {
    expect(
      sortLibrary(entries, LibrarySort.recentlyPlayed).map((e) => e.book.id),
      [3, 1, 2],
    );
  });
}
