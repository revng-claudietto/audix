import 'package:flutter_test/flutter_test.dart';

import 'package:audix/core/audio/audiobook_handler.dart';

void main() {
  test('resumeRewindFor is graduated by how long playback was paused', () {
    expect(resumeRewindFor(const Duration(seconds: 3)), Duration.zero);
    expect(resumeRewindFor(const Duration(seconds: 9)), Duration.zero);
    expect(resumeRewindFor(const Duration(seconds: 30)),
        const Duration(seconds: 5));
    expect(resumeRewindFor(const Duration(minutes: 10)),
        const Duration(seconds: 10));
    expect(resumeRewindFor(const Duration(hours: 3)),
        const Duration(seconds: 20));
  });
}
