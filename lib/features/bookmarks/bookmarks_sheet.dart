import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/audio_providers.dart';
import '../../core/database/database.dart';
import '../../core/providers.dart';
import '../../core/util/format.dart';

/// True if a bookmark's note / book title / "Chapter N" label contains [query].
bool bookmarkMatches(
  String? note,
  int chapterIndex,
  String query, {
  String? bookTitle,
}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  final haystack =
      '${note ?? ''} ${bookTitle ?? ''} chapter ${chapterIndex + 1}'
          .toLowerCase();
  return haystack.contains(q);
}

/// Icon representing how a bookmark was created.
IconData bookmarkKindIcon(BookmarkKind kind) => switch (kind) {
      BookmarkKind.manual => Icons.bookmark,
      BookmarkKind.autoStart => Icons.play_circle_outline,
      BookmarkKind.autoStop => Icons.pause_circle_outline,
    };

/// Short label for a bookmark kind.
String bookmarkKindLabel(BookmarkKind kind) => switch (kind) {
      BookmarkKind.manual => 'Bookmark',
      BookmarkKind.autoStart => 'Started',
      BookmarkKind.autoStop => 'Stopped',
    };

/// A reusable rounded filter field for the bookmark views.
class BookmarkSearchField extends StatelessWidget {
  const BookmarkSearchField({
    super.key,
    required this.controller,
    required this.onChanged,
    this.hintText = 'Filter bookmarks…',
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        hintText: hintText,
        prefixIcon: const Icon(Icons.search),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.clear),
                tooltip: 'Clear',
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

/// Opens the per-book bookmarks bottom sheet for the current book.
void showBookmarksSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => const _BookmarksSheet(),
  );
}

class _BookmarksSheet extends ConsumerStatefulWidget {
  const _BookmarksSheet();

  @override
  ConsumerState<_BookmarksSheet> createState() => _BookmarksSheetState();
}

class _BookmarksSheetState extends ConsumerState<_BookmarksSheet> {
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
    final bookmarks =
        ref.watch(currentBookmarksProvider).value ?? const <Bookmark>[];
    final controller = ref.read(playerControllerProvider);
    final bookId = ref.watch(currentBookIdProvider);

    if (bookmarks.isEmpty) {
      return const SafeArea(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: Text('No bookmarks yet')),
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

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: BookmarkSearchField(
              controller: _controller,
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          if (hasAuto)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
              child: Row(
                children: [
                  FilterChip(
                    label: const Text('Manual only'),
                    selected: _manualOnly,
                    onSelected: (v) => setState(() => _manualOnly = v),
                  ),
                  const Spacer(),
                  if (bookId != null)
                    TextButton.icon(
                      icon: const Icon(Icons.auto_delete_outlined, size: 18),
                      label: const Text('Clear auto'),
                      onPressed: () => ref
                          .read(databaseProvider)
                          .clearAutoBookmarks(bookId),
                    ),
                ],
              ),
            ),
          Flexible(
            child: filtered.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No matching bookmarks'),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: filtered.length,
                    itemBuilder: (context, i) {
                      final b = filtered[i];
                      return BookmarkTile(
                        bookmark: b,
                        onTap: () {
                          controller
                              .seek(Duration(milliseconds: b.positionMs));
                          Navigator.pop(context);
                        },
                        onEditNote: () =>
                            showBookmarkNoteDialog(context, ref, b.id, b.note),
                        onDelete: () =>
                            ref.read(databaseProvider).deleteBookmark(b.id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// A single bookmark row showing its kind, location and the time it was added.
class BookmarkTile extends StatelessWidget {
  const BookmarkTile({
    super.key,
    required this.bookmark,
    required this.onTap,
    required this.onEditNote,
    required this.onDelete,
    this.bookTitle,
  });

  final Bookmark bookmark;
  final VoidCallback onTap;
  final VoidCallback onEditNote;
  final VoidCallback onDelete;

  /// When set (global list), shown in the subtitle to identify the book.
  final String? bookTitle;

  @override
  Widget build(BuildContext context) {
    final b = bookmark;
    final chapterNo = b.chapterIndex + 1;
    final pos = formatDuration(Duration(milliseconds: b.positionMs));
    final when = formatTimestamp(b.createdAt);
    final hasNote = b.note?.isNotEmpty == true;
    final title = hasNote ? b.note! : bookmarkKindLabel(b.kind);
    final where = 'Chapter $chapterNo • $pos';
    final subtitle = [
      if (bookTitle != null) bookTitle,
      where,
      when,
    ].join(' • ');

    return ListTile(
      leading: Icon(bookmarkKindIcon(b.kind)),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: PopupMenuButton<String>(
        onSelected: (v) {
          if (v == 'note') onEditNote();
          if (v == 'delete') onDelete();
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'note', child: Text('Edit note')),
          PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
      onTap: onTap,
    );
  }
}

/// Shows a dialog to add/edit a bookmark's note.
Future<void> showBookmarkNoteDialog(
  BuildContext context,
  WidgetRef ref,
  int bookmarkId,
  String? currentNote,
) async {
  final db = ref.read(databaseProvider);
  final textController = TextEditingController(text: currentNote ?? '');
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Bookmark note'),
      content: TextField(
        controller: textController,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'Note'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, textController.text.trim()),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  if (result == null) return;
  await db.updateBookmarkNote(bookmarkId, result.isEmpty ? null : result);
}
