import 'package:flutter_test/flutter_test.dart';

import 'package:audix/core/subtitle/subtitle_parser.dart';

void main() {
  group('SubtitleParser.parse', () {
    test('parses a WebVTT file with a header and hour-less timestamps', () {
      const vtt = '''
WEBVTT

00:00.000 --> 00:02.500
Hello there.

00:02.500 --> 00:05.000
This is a transcript.
''';
      final cues = SubtitleParser.parse(vtt);
      expect(cues, hasLength(2));
      expect(cues[0].startMs, 0);
      expect(cues[0].endMs, 2500);
      expect(cues[0].text, 'Hello there.');
      expect(cues[1].startMs, 2500);
      expect(cues[1].text, 'This is a transcript.');
      expect(cues[1].index, 1);
    });

    test('parses HH:MM:SS.mmm timestamps', () {
      const vtt = '''
WEBVTT

01:02:03.400 --> 01:02:05.000
Deep in the book.
''';
      final cues = SubtitleParser.parse(vtt);
      // 1h2m3.4s = 3723400ms.
      expect(cues.single.startMs, 3723400);
    });

    test('parses SRT (comma millis, numeric index lines)', () {
      const srt = '''
1
00:00:00,000 --> 00:00:01,000
First line.

2
00:00:01,000 --> 00:00:02,000
Second line.
''';
      final cues = SubtitleParser.parse(srt);
      expect(cues, hasLength(2));
      expect(cues[0].startMs, 0);
      expect(cues[0].endMs, 1000);
      expect(cues[0].text, 'First line.');
      expect(cues[1].startMs, 1000);
      expect(cues[1].text, 'Second line.');
    });

    test('joins multi-line cue text with spaces and strips inline tags', () {
      const vtt = '''
WEBVTT

00:00.000 --> 00:03.000
<c.yellow>Line one</c>
line two
''';
      final cues = SubtitleParser.parse(vtt);
      expect(cues.single.text, 'Line one line two');
    });

    test('ignores NOTE blocks and cue identifiers', () {
      const vtt = '''
WEBVTT

NOTE This is a comment that mentions nothing timed.

intro
00:00.000 --> 00:01.000
Real text.
''';
      final cues = SubtitleParser.parse(vtt);
      expect(cues, hasLength(1));
      expect(cues.single.text, 'Real text.');
    });

    test('sorts out-of-order cues and re-indexes', () {
      const vtt = '''
WEBVTT

00:00:05.000 --> 00:00:06.000
Second.

00:00:01.000 --> 00:00:02.000
First.
''';
      final cues = SubtitleParser.parse(vtt);
      expect(cues.map((c) => c.text).toList(), ['First.', 'Second.']);
      expect(cues[0].index, 0);
      expect(cues[1].index, 1);
    });

    test('returns nothing for content without timing lines', () {
      expect(SubtitleParser.parse('WEBVTT\n\njust prose\n'), isEmpty);
      expect(SubtitleParser.parse(''), isEmpty);
    });
  });
}
