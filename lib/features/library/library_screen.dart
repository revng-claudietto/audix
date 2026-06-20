import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/audio_providers.dart';
import '../../core/database/database.dart';
import '../../core/providers.dart';
import '../../core/storage/file_paths.dart';
import '../player/player_screen.dart';
import 'book_cover.dart';

enum LibrarySort { recentlyPlayed, recentlyAdded, title, author }

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  LibrarySort _sort = LibrarySort.recentlyPlayed;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entriesAsync = ref.watch(libraryEntriesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
        actions: [
          PopupMenuButton<LibrarySort>(
            icon: const Icon(Icons.sort),
            tooltip: 'Sort',
            initialValue: _sort,
            onSelected: (s) => setState(() => _sort = s),
            itemBuilder: (_) => const [
              PopupMenuItem(
                  value: LibrarySort.recentlyPlayed,
                  child: Text('Recently played')),
              PopupMenuItem(
                  value: LibrarySort.recentlyAdded,
                  child: Text('Recently added')),
              PopupMenuItem(value: LibrarySort.title, child: Text('Title')),
              PopupMenuItem(value: LibrarySort.author, child: Text('Author')),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Import audiobook',
            onPressed: _import,
          ),
        ],
      ),
      body: entriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (entries) {
          if (entries.isEmpty) {
            return _EmptyLibrary(onImport: _import);
          }

          final continueList = [
            for (final e in entries)
              if (e.positionMs > 0 && !e.book.completed) e,
          ]..sort((a, b) => (b.updatedAt ?? DateTime(0))
              .compareTo(a.updatedAt ?? DateTime(0)));

          final query = _query.trim();
          final all = sortLibrary(filterLibrary(entries, query), _sort);

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    hintText: 'Search ${entries.length} books…',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            tooltip: 'Clear',
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                          ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(28),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  children: [
                    if (query.isEmpty && continueList.isNotEmpty) ...[
                      const _SectionHeader('Continue listening'),
                      SizedBox(
                        height: 188,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: continueList.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 12),
                          itemBuilder: (context, i) => _ContinueCard(
                            entry: continueList[i],
                            onTap: () => _openBook(continueList[i].book),
                          ),
                        ),
                      ),
                    ],
                    _SectionHeader(query.isEmpty ? 'All books' : 'Results'),
                    for (final e in all)
                      _BookTile(
                        entry: e,
                        onTap: () => _openBook(e.book),
                        onDelete: () => _deleteBook(e.book),
                      ),
                    if (all.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: Text('No matches')),
                      ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openBook(Book book) async {
    await ref.read(playerControllerProvider).openBook(book);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PlayerScreen()),
    );
  }

  Future<void> _deleteBook(Book book) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete book?'),
        content: Text('Remove "${book.title}" and its files from this device?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(databaseProvider).deleteBook(book.id);
    await FilePaths.deleteBookDir(book.id);
  }

  Future<void> _import() async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['m4b', 'cue'],
      allowMultiple: true,
    );
    if (result == null) return;

    String? m4b;
    String? cue;
    for (final file in result.files) {
      final path = file.path;
      if (path == null) continue;
      final lower = path.toLowerCase();
      if (lower.endsWith('.m4b')) m4b = path;
      if (lower.endsWith('.cue')) cue = path;
    }
    if (m4b == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Select an .m4b file (optionally with its .cue).'),
        ),
      );
      return;
    }

    if (!mounted) return;
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    ));
    try {
      await ref
          .read(localImporterProvider)
          .importBook(m4bSourcePath: m4b, cueSourcePath: cue);
      if (mounted) Navigator.of(context).pop();
      messenger.showSnackBar(const SnackBar(content: Text('Imported')));
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(content: Text('Import failed: $e')));
    }
  }
}

String _timeLeft(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  if (h > 0) return '${h}h ${m}m left';
  if (m > 0) return '${m}m left';
  return '<1m left';
}

/// Filters [entries] by a case-insensitive substring on title/author.
List<LibraryEntry> filterLibrary(List<LibraryEntry> entries, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return entries;
  return [
    for (final e in entries)
      if (e.book.title.toLowerCase().contains(q) ||
          (e.book.author?.toLowerCase().contains(q) ?? false))
        e,
  ];
}

/// Returns a new list of [entries] sorted by [sort].
List<LibraryEntry> sortLibrary(List<LibraryEntry> entries, LibrarySort sort) {
  return [...entries]..sort((a, b) => _compareEntries(a, b, sort));
}

int _compareEntries(LibraryEntry a, LibraryEntry b, LibrarySort sort) {
  switch (sort) {
    case LibrarySort.recentlyPlayed:
      return (b.updatedAt ?? DateTime(0)).compareTo(a.updatedAt ?? DateTime(0));
    case LibrarySort.recentlyAdded:
      return b.book.addedAt.compareTo(a.book.addedAt);
    case LibrarySort.title:
      return a.book.title.toLowerCase().compareTo(b.book.title.toLowerCase());
    case LibrarySort.author:
      return (a.book.author ?? '')
          .toLowerCase()
          .compareTo((b.book.author ?? '').toLowerCase());
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _BookTile extends StatelessWidget {
  const _BookTile({
    required this.entry,
    required this.onTap,
    required this.onDelete,
  });

  final LibraryEntry entry;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final book = entry.book;
    final scheme = Theme.of(context).colorScheme;
    final hasProgress = book.completed || entry.positionMs > 0;
    final fraction = book.durationMs > 0
        ? (entry.positionMs / book.durationMs).clamp(0.0, 1.0)
        : 0.0;
    final remaining = Duration(
      milliseconds: (book.durationMs - entry.positionMs).clamp(0, book.durationMs),
    );

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            BookCover(coverPath: book.coverPath, size: 56),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(book.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (book.author != null)
                    Text(
                      book.author!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  if (hasProgress) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: book.completed ? 1.0 : fraction,
                              minHeight: 4,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          book.completed ? 'Finished' : _timeLeft(remaining),
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'delete') onDelete();
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.entry, required this.onTap});

  final LibraryEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final book = entry.book;
    final fraction = book.durationMs > 0
        ? (entry.positionMs / book.durationMs).clamp(0.0, 1.0)
        : 0.0;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 130,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BookCover(coverPath: book.coverPath, size: 130, radius: 12),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: fraction, minHeight: 4),
            ),
            const SizedBox(height: 4),
            Text(
              book.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.onImport});

  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.headphones,
              size: 72,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'No audiobooks yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Import a book from this device, or add a server in the '
              'Servers tab to download one.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onImport,
              icon: const Icon(Icons.add),
              label: const Text('Import from device'),
            ),
          ],
        ),
      ),
    );
  }
}
