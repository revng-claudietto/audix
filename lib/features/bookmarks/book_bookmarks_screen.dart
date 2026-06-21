import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/audio_providers.dart';
import '../../core/database/database.dart';
import '../../core/providers.dart';
import '../player/player_screen.dart';
import 'bookmarks_sheet.dart';

/// All bookmarks (manual + automatic start/stop) for a single book.
class BookBookmarksScreen extends ConsumerStatefulWidget {
  const BookBookmarksScreen({super.key, required this.book});

  final Book book;

  @override
  ConsumerState<BookBookmarksScreen> createState() =>
      _BookBookmarksScreenState();
}

class _BookBookmarksScreenState extends ConsumerState<BookBookmarksScreen> {
  final _controller = TextEditingController();
  String _query = '';
  bool _manualOnly = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final book = widget.book;
    final async = ref.watch(bookmarksForProvider(book.id));

    return Scaffold(
      appBar: AppBar(
        title: Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (bookmarks) {
          if (bookmarks.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No bookmarks yet.\n'
                  'Play this book to capture start/stop bookmarks, or tap '
                  '"Bookmark" in the player.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final hasAuto = bookmarks.any((b) => b.kind != BookmarkKind.manual);
          final filtered = [
            for (final b in bookmarks)
              if ((!_manualOnly || b.kind == BookmarkKind.manual) &&
                  bookmarkMatches(b.note, b.chapterIndex, _query))
                b,
          ];

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: BookmarkSearchField(
                  controller: _controller,
                  onChanged: (v) => setState(() => _query = v),
                  hintText: 'Search ${bookmarks.length} bookmarks…',
                ),
              ),
              if (hasAuto)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 4, 0),
                  child: Row(
                    children: [
                      FilterChip(
                        label: const Text('Manual only'),
                        selected: _manualOnly,
                        onSelected: (v) => setState(() => _manualOnly = v),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        icon: const Icon(Icons.auto_delete_outlined, size: 18),
                        label: const Text('Clear auto'),
                        onPressed: () => ref
                            .read(databaseProvider)
                            .clearAutoBookmarks(book.id),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(child: Text('No matching bookmarks'))
                    : ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, i) {
                          final b = filtered[i];
                          return BookmarkTile(
                            bookmark: b,
                            onTap: () => _open(b.positionMs),
                            onEditNote: () => showBookmarkNoteDialog(
                                context, ref, b.id, b.note),
                            onDelete: () =>
                                ref.read(databaseProvider).deleteBookmark(b.id),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _open(int positionMs) async {
    await ref
        .read(playerControllerProvider)
        .openBookmark(widget.book, positionMs);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PlayerScreen()),
    );
  }
}
