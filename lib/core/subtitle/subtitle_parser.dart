/// A single timed line parsed from a subtitle / transcript file.
class SubtitleCue {
  const SubtitleCue({
    required this.index,
    required this.startMs,
    required this.endMs,
    required this.text,
  });

  /// Zero-based position in the (start-sorted) transcript.
  final int index;
  final int startMs;
  final int endMs;
  final String text;
}

/// Parser for WebVTT (`.vtt`) and SubRip (`.srt`) subtitle files.
///
/// Both formats are blocks separated by blank lines, each with a
/// `start --> end` timing line followed by one or more text lines. The only
/// differences that matter here are the `WEBVTT` header, SRT's leading
/// cue-number line, and the fractional-seconds separator (`.` in VTT, `,` in
/// SRT) — this parser accepts either, so a single pass handles both formats.
class SubtitleParser {
  /// `[HH:]MM:SS.mmm` with `.` or `,` before the (1–3 digit) milliseconds.
  static final _timeRe = RegExp(r'(?:(\d+):)?(\d{1,3}):(\d{2})[.,](\d{1,3})');

  /// Inline VTT styling tags such as `<c.foo>`, `</c>`, `<00:00:01.000>`.
  static final _tagRe = RegExp(r'<[^>]*>');

  static int _timeToMs(RegExpMatch m) {
    final hours = int.parse(m.group(1) ?? '0');
    final minutes = int.parse(m.group(2)!);
    final seconds = int.parse(m.group(3)!);
    // Right-pad so `.5` is 500ms, not 5ms; then take the first 3 digits.
    final millis = int.parse(m.group(4)!.padRight(3, '0').substring(0, 3));
    return ((hours * 60 + minutes) * 60 + seconds) * 1000 + millis;
  }

  /// Parses [content], returning cues sorted by start time and re-indexed.
  static List<SubtitleCue> parse(String content) {
    // Normalise newlines and drop a leading UTF-8 BOM.
    final text = content
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceFirst('﻿', '');
    final lines = text.split('\n');

    final parsed = <SubtitleCue>[];
    var i = 0;
    while (i < lines.length) {
      final line = lines[i];
      // A timing line is the only one carrying two timestamps around `-->`.
      if (line.contains('-->')) {
        final times = _timeRe.allMatches(line).toList();
        if (times.length >= 2) {
          final startMs = _timeToMs(times[0]);
          final endMs = _timeToMs(times[1]);
          final buffer = StringBuffer();
          i++;
          // Text runs until the next blank line (or end of file).
          while (i < lines.length && lines[i].trim().isNotEmpty) {
            final piece = lines[i].replaceAll(_tagRe, '').trim();
            if (piece.isNotEmpty) {
              if (buffer.isNotEmpty) buffer.write(' ');
              buffer.write(piece);
            }
            i++;
          }
          final body = buffer.toString();
          if (body.isNotEmpty) {
            parsed.add(SubtitleCue(
              index: 0,
              startMs: startMs,
              endMs: endMs < startMs ? startMs : endMs,
              text: body,
            ));
          }
          continue;
        }
      }
      i++;
    }

    parsed.sort((a, b) => a.startMs.compareTo(b.startMs));
    return [
      for (var k = 0; k < parsed.length; k++)
        SubtitleCue(
          index: k,
          startMs: parsed[k].startMs,
          endMs: parsed[k].endMs,
          text: parsed[k].text,
        ),
    ];
  }
}
