import 'dart:convert';
import 'dart:typed_data';

import '../database/database.dart';
import 'subtitle_parser.dart';

/// Parses subtitle/transcript files and stores their cues in the database.
///
/// Cues live entirely in the drift database (like chapters), so attaching a
/// transcript works identically on mobile and the web with no filesystem.
class SubtitleService {
  SubtitleService(this.db);

  final AppDatabase db;

  /// Parses [bytes] (a `.vtt`/`.srt` file) and stores the resulting cues for
  /// [bookId], replacing any existing transcript. Returns the number of lines.
  Future<int> attach(int bookId, Uint8List bytes) async {
    final content = utf8.decode(bytes, allowMalformed: true);
    final cues = SubtitleParser.parse(content);
    await db.replaceSubtitles(bookId, [
      for (final c in cues)
        SubtitleCuesCompanion.insert(
          bookId: bookId,
          cueIndex: c.index,
          startMs: c.startMs,
          endMs: c.endMs,
          content: c.text,
        ),
    ]);
    return cues.length;
  }
}
