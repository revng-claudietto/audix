import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/database.dart';
import '../../core/download/download_service.dart';
import '../../core/remote/remote_providers.dart';
import '../../core/remote/remote_source.dart';
import '../../core/storage/storage_permission.dart';

class ServerBrowseScreen extends ConsumerStatefulWidget {
  const ServerBrowseScreen({
    super.key,
    required this.server,
    this.path,
    this.title,
  });

  final Server server;

  /// Current folder URL. Defaults to the server's base URL.
  final String? path;

  /// Folder name shown in the app bar (and used as the downloaded book title).
  final String? title;

  @override
  ConsumerState<ServerBrowseScreen> createState() => _ServerBrowseScreenState();
}

class _ServerBrowseScreenState extends ConsumerState<ServerBrowseScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String get _url => widget.path ?? widget.server.baseUrl;

  @override
  Widget build(BuildContext context) {
    final server = widget.server;
    final url = _url;
    final listing = ref.watch(remoteListingProvider((server.id, url)));
    final downloads = ref.watch(downloadsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(widget.title ?? server.name)),
      body: listing.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ListingError(
          message: '$e',
          onRetry: () =>
              ref.invalidate(remoteListingProvider((server.id, url))),
        ),
        data: (entries) {
          final m4b = _firstMatch(
              entries, (e) => !e.isDir && e.name.toLowerCase().endsWith('.m4b'));
          final cue = _firstMatch(
              entries, (e) => !e.isDir && e.name.toLowerCase().endsWith('.cue'));
          final subtitle = _firstMatch(
              entries,
              (e) =>
                  !e.isDir &&
                  (e.name.toLowerCase().endsWith('.vtt') ||
                      e.name.toLowerCase().endsWith('.srt')));
          final dirs = entries.where((e) => e.isDir).toList();
          final query = _query.trim().toLowerCase();
          final filtered = query.isEmpty
              ? dirs
              : dirs
                  .where((d) => d.name.toLowerCase().contains(query))
                  .toList();

          return Column(
            children: [
              if (dirs.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (v) => setState(() => _query = v),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      hintText: 'Filter ${dirs.length} folders…',
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
                child: RefreshIndicator(
                  onRefresh: () async =>
                      ref.invalidate(remoteListingProvider((server.id, url))),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      if (m4b != null)
                        _DownloadBanner(
                          folderName: widget.title ?? server.name,
                          progress: downloads[url],
                          hasChapters: cue != null,
                          hasSubtitles: subtitle != null,
                          onDownload: () =>
                              _download(context, url, m4b, cue, subtitle),
                          onCancel: () =>
                              ref.read(downloadsProvider.notifier).cancel(url),
                        ),
                      for (final dir in filtered)
                        ListTile(
                          leading: const Icon(Icons.folder),
                          title: Text(dir.name),
                          trailing: downloads.containsKey(dir.url.toString())
                              ? _CancelableProgress(
                                  value: downloads[dir.url.toString()]!,
                                  onCancel: () => ref
                                      .read(downloadsProvider.notifier)
                                      .cancel(dir.url.toString()),
                                )
                              : const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ServerBrowseScreen(
                                server: server,
                                path: dir.url.toString(),
                                title: dir.name,
                              ),
                            ),
                          ),
                        ),
                      if (entries.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(child: Text('This folder is empty')),
                        ),
                      if (dirs.isNotEmpty && filtered.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(32),
                          child: Center(
                            child: Text('No folders match "$_query"'),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _download(BuildContext context, String url, RemoteEntry m4b,
      RemoteEntry? cue, RemoteEntry? subtitle) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(downloadsProvider.notifier).downloadBookAt(
            server: widget.server,
            folderName: widget.title ?? widget.server.name,
            folderKey: url,
            m4b: m4b,
            cue: cue,
            subtitle: subtitle,
          );
      messenger.showSnackBar(
        const SnackBar(content: Text('Downloaded to library')),
      );
    } on DownloadCanceledException {
      messenger.showSnackBar(
        const SnackBar(content: Text('Download canceled')),
      );
    } on StoragePermissionException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Download failed: $e')));
    }
  }
}

RemoteEntry? _firstMatch(
    List<RemoteEntry> entries, bool Function(RemoteEntry) test) {
  for (final entry in entries) {
    if (test(entry)) return entry;
  }
  return null;
}

class _DownloadBanner extends StatelessWidget {
  const _DownloadBanner({
    required this.folderName,
    required this.progress,
    required this.hasChapters,
    required this.hasSubtitles,
    required this.onDownload,
    required this.onCancel,
  });

  final String folderName;
  final double? progress;
  final bool hasChapters;
  final bool hasSubtitles;
  final VoidCallback onDownload;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.menu_book),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    folderName,
                    style: Theme.of(context).textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // What this book ships with, read from the server folder's files.
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                const _FeatureChip(icon: Icons.headphones, label: 'Audio'),
                if (hasChapters)
                  const _FeatureChip(icon: Icons.list_alt, label: 'Chapters'),
                if (hasSubtitles)
                  const _FeatureChip(
                      icon: Icons.subtitles_outlined, label: 'Subtitles'),
              ],
            ),
            const SizedBox(height: 12),
            if (progress != null) ...[
              LinearProgressIndicator(value: progress),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text('Downloading… ${(progress! * 100).round()}%'),
                  ),
                  TextButton.icon(
                    onPressed: onCancel,
                    icon: const Icon(Icons.close),
                    label: const Text('Cancel'),
                  ),
                ],
              ),
            ] else
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: onDownload,
                  icon: const Icon(Icons.download),
                  label: const Text('Download'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A compact labelled pill describing one capability a book offers (audio,
/// chapters, subtitles), shown in the download banner while browsing a server.
class _FeatureChip extends StatelessWidget {
  const _FeatureChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: scheme.onSecondaryContainer),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: scheme.onSecondaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}

/// A small circular progress ring with a tappable cancel (✕) at its center,
/// used as a folder tile's trailing widget while that folder is downloading.
class _CancelableProgress extends StatelessWidget {
  const _CancelableProgress({required this.value, required this.onCancel});

  final double value;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 30,
            height: 30,
            child: CircularProgressIndicator(value: value, strokeWidth: 2),
          ),
          IconButton(
            iconSize: 16,
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            tooltip: 'Cancel download',
            icon: const Icon(Icons.close),
            onPressed: onCancel,
          ),
        ],
      ),
    );
  }
}

class _ListingError extends StatelessWidget {
  const _ListingError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 56),
            const SizedBox(height: 16),
            const Text(
              "Couldn't load this folder",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            const Text(
              'Check the URL and credentials (a 401 means wrong username or '
              'password).',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
