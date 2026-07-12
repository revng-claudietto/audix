import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/audio_providers.dart';
import '../../core/database/database.dart';
import '../../core/util/format.dart';

/// A full-screen, lyrics-style transcript for the currently playing book.
///
/// The line at the current playback position is shown at full strength while
/// the rest is desaturated; the view auto-scrolls to keep it centred, and
/// tapping any line seeks (and plays) from there. Scrolling by hand pauses the
/// auto-follow until the "jump to current" button is tapped.
///
/// The app-bar search filters the transcript to lines containing the query
/// (highlighted, with their timestamp); tapping a result jumps playback there
/// and returns to the lyrics view.
class TranscriptScreen extends ConsumerStatefulWidget {
  const TranscriptScreen({super.key});

  @override
  ConsumerState<TranscriptScreen> createState() => _TranscriptScreenState();
}

class _TranscriptScreenState extends ConsumerState<TranscriptScreen> {
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();

  /// Attached to the active line so we can centre it via [Scrollable.ensureVisible].
  final _activeKey = GlobalKey();

  /// Rough per-line height, used only to jump near a far-off line before the
  /// exact centring pass (lines are lazily built, so a target off-screen has no
  /// context to scroll to yet).
  static const _estimatedExtent = 64.0;

  bool _following = true;
  bool _searching = false;
  String _query = '';
  int _activeIndex = -2; // sentinel so the first real value triggers a scroll.

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// Index of the last cue that has started at or before [posMs], or -1 before
  /// the first cue begins (binary search over start times).
  int _activeFor(List<SubtitleCueRow> cues, int posMs) {
    if (cues.isEmpty || posMs < cues.first.startMs) return -1;
    var lo = 0;
    var hi = cues.length - 1;
    var ans = 0;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (cues[mid].startMs <= posMs) {
        ans = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return ans;
  }

  /// Centres line [index], jumping near it first if it isn't built yet.
  void _scrollTo(int index, {required bool animate}) {
    if (index < 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final ctx = _activeKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.5,
          duration: animate ? const Duration(milliseconds: 320) : Duration.zero,
          curve: Curves.easeInOut,
        );
        return;
      }
      // Far off-screen: jump to an estimate so it enters the build window, then
      // centre precisely on the next frame.
      final target = (index * _estimatedExtent)
          .clamp(0.0, _scrollController.position.maxScrollExtent);
      _scrollController.jumpTo(target);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final c = _activeKey.currentContext;
        if (c != null) {
          Scrollable.ensureVisible(c, alignment: 0.5, duration: Duration.zero);
        }
      });
    });
  }

  void _resumeFollowing() {
    setState(() => _following = true);
    _scrollTo(_activeIndex, animate: true);
  }

  void _openSearch() => setState(() => _searching = true);

  void _closeSearch() {
    _searchController.clear();
    setState(() {
      _searching = false;
      _query = '';
    });
  }

  void _seekToCue(SubtitleCueRow cue, int index) {
    final controller = ref.read(playerControllerProvider);
    controller.seek(Duration(milliseconds: cue.startMs));
    controller.play();
    _activeIndex = index;
    setState(() => _following = true);
    _scrollTo(index, animate: true);
  }

  /// Tapping a search result leaves search and returns to the lyrics view
  /// centred on (and playing from) the tapped line.
  void _jumpFromSearch(SubtitleCueRow cue, int index) {
    _searchController.clear();
    setState(() {
      _searching = false;
      _query = '';
    });
    _seekToCue(cue, index);
  }

  @override
  Widget build(BuildContext context) {
    final cues = ref.watch(currentSubtitlesProvider).value ?? const [];
    final posMs = ref.watch(positionProvider).value?.inMilliseconds ?? 0;
    final playing = ref.watch(playbackStateProvider).value?.playing ?? false;
    final controller = ref.read(playerControllerProvider);
    final scheme = Theme.of(context).colorScheme;

    final active = _activeFor(cues, posMs);
    if (active != _activeIndex) {
      _activeIndex = active;
      if (_following && !_searching) _scrollTo(active, animate: true);
    }

    final query = _query.trim();
    final searchMode = _searching && query.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        leading: _searching
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Close search',
                onPressed: _closeSearch,
              )
            : null,
        title: _searching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: 'Search transcript…',
                  border: InputBorder.none,
                ),
                onChanged: (v) => setState(() => _query = v),
              )
            : const Text('Transcript'),
        actions: [
          if (cues.isNotEmpty && !_searching)
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: 'Search',
              onPressed: _openSearch,
            ),
          if (_searching && _query.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Clear',
              onPressed: () {
                _searchController.clear();
                setState(() => _query = '');
              },
            ),
        ],
      ),
      body: cues.isEmpty
          ? const Center(child: Text('No transcript for this book.'))
          : searchMode
              ? _buildResults(cues, query.toLowerCase(), scheme)
              : _buildTranscript(cues),
      floatingActionButton: (searchMode || _following || cues.isEmpty)
          ? null
          : FloatingActionButton.small(
              onPressed: _resumeFollowing,
              tooltip: 'Jump to current line',
              child: const Icon(Icons.my_location),
            ),
      bottomNavigationBar: cues.isEmpty
          ? null
          : _MiniControls(
              playing: playing,
              positionMs: posMs,
              onRewind: controller.skipBackward,
              onForward: controller.skipForward,
              onToggle: controller.togglePlayPause,
              color: scheme.surfaceContainerHighest,
            ),
    );
  }

  Widget _buildTranscript(List<SubtitleCueRow> cues) {
    return NotificationListener<UserScrollNotification>(
      onNotification: (n) {
        // A user drag/fling pauses auto-follow (programmatic scrolls do not
        // emit UserScrollNotifications).
        if (n.direction != ScrollDirection.idle && _following) {
          setState(() => _following = false);
        }
        return false;
      },
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
        itemCount: cues.length,
        itemBuilder: (context, i) {
          final isActive = i == _activeIndex;
          return _CueLine(
            key: isActive ? _activeKey : null,
            text: cues[i].content,
            active: isActive,
            onTap: () => _seekToCue(cues[i], i),
          );
        },
      ),
    );
  }

  Widget _buildResults(
      List<SubtitleCueRow> cues, String lowerQuery, ColorScheme scheme) {
    final matches = <int>[
      for (var i = 0; i < cues.length; i++)
        if (cues[i].content.toLowerCase().contains(lowerQuery)) i,
    ];
    if (matches.isEmpty) {
      return const Center(child: Text('No matches.'));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Text(
            '${matches.length} ${matches.length == 1 ? 'match' : 'matches'}',
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 96),
            itemCount: matches.length,
            itemBuilder: (context, k) {
              final i = matches[k];
              return _ResultTile(
                text: cues[i].content,
                query: _query.trim(),
                startMs: cues[i].startMs,
                onTap: () => _jumpFromSearch(cues[i], i),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Splits [text] into styled spans, emphasising every case-insensitive
/// occurrence of [query] with [match] over [base].
Widget _highlight(String text, String query, TextStyle base, TextStyle match) {
  final q = query.toLowerCase();
  if (q.isEmpty) return Text(text, style: base);
  final lower = text.toLowerCase();
  final spans = <TextSpan>[];
  var start = 0;
  while (start < text.length) {
    final idx = lower.indexOf(q, start);
    if (idx < 0) {
      spans.add(TextSpan(text: text.substring(start), style: base));
      break;
    }
    if (idx > start) {
      spans.add(TextSpan(text: text.substring(start, idx), style: base));
    }
    spans.add(TextSpan(text: text.substring(idx, idx + q.length), style: match));
    start = idx + q.length;
  }
  return Text.rich(TextSpan(children: spans));
}

/// A single transcript line: bright when [active], desaturated otherwise, with
/// a smooth transition between the two.
class _CueLine extends StatelessWidget {
  const _CueLine({
    super.key,
    required this.text,
    required this.active,
    required this.onTap,
  });

  final String text;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = Theme.of(context).textTheme.titleMedium!;
    final style = active
        ? base.copyWith(
            color: scheme.onSurface,
            fontWeight: FontWeight.w700,
            height: 1.35,
          )
        : base.copyWith(
            color: scheme.onSurface.withValues(alpha: 0.35),
            fontWeight: FontWeight.w400,
            height: 1.35,
          );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 220),
          style: style,
          child: Text(text),
        ),
      ),
    );
  }
}

/// A search hit: the line's timestamp plus its text with the query highlighted.
class _ResultTile extends StatelessWidget {
  const _ResultTile({
    required this.text,
    required this.query,
    required this.startMs,
    required this.onTap,
  });

  final String text;
  final String query;
  final int startMs;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = Theme.of(context)
        .textTheme
        .bodyLarge!
        .copyWith(color: scheme.onSurface, height: 1.3);
    final match = base.copyWith(
      fontWeight: FontWeight.w700,
      color: scheme.onPrimaryContainer,
      backgroundColor: scheme.primaryContainer,
    );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2, right: 12),
              child: Text(
                formatDuration(Duration(milliseconds: startMs)),
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: scheme.primary),
              ),
            ),
            Expanded(child: _highlight(text, query, base, match)),
          ],
        ),
      ),
    );
  }
}

/// Compact transport bar shown under the transcript so playback stays
/// controllable without leaving the screen.
class _MiniControls extends StatelessWidget {
  const _MiniControls({
    required this.playing,
    required this.positionMs,
    required this.onRewind,
    required this.onForward,
    required this.onToggle,
    required this.color,
  });

  final bool playing;
  final int positionMs;
  final VoidCallback onRewind;
  final VoidCallback onForward;
  final VoidCallback onToggle;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              const SizedBox(width: 16),
              Text(
                formatDuration(Duration(milliseconds: positionMs)),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const Spacer(),
              IconButton(
                iconSize: 30,
                icon: const Icon(Icons.replay_30),
                tooltip: 'Back',
                onPressed: onRewind,
              ),
              IconButton(
                iconSize: 40,
                icon: Icon(playing ? Icons.pause_circle : Icons.play_circle),
                tooltip: playing ? 'Pause' : 'Play',
                onPressed: onToggle,
              ),
              IconButton(
                iconSize: 30,
                icon: const Icon(Icons.forward_30),
                tooltip: 'Forward',
                onPressed: onForward,
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}
