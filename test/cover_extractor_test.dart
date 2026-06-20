import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:audix/core/library/cover_extractor.dart';

List<int> _u32(int v) =>
    [(v >> 24) & 0xff, (v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff];

List<int> _box(String type, List<int> payload) =>
    [..._u32(8 + payload.length), ...type.codeUnits, ...payload];

void main() {
  test('extracts embedded cover from a synthetic m4b', () async {
    final image = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
    final data = _box('data', [
      0, 0, 0, 13, // type indicator (JPEG)
      0, 0, 0, 0, // locale
      ...image,
    ]);
    final covr = _box('covr', data);
    final ilst = _box('ilst', covr);
    final meta = _box('meta', [0, 0, 0, 0, ...ilst]); // full box version/flags
    final udta = _box('udta', meta);
    final moov = _box('moov', udta);
    // Surround with unrelated boxes so we exercise the top-level scanner.
    final ftyp = _box('ftyp', [0, 0, 0, 0]);
    final mdat = _box('mdat', List<int>.filled(32, 0));
    final bytes = Uint8List.fromList([...ftyp, ...moov, ...mdat]);

    final dir = await Directory.systemTemp.createTemp('cover_test');
    final file = File('${dir.path}/sample.m4b');
    await file.writeAsBytes(bytes);

    final cover = await CoverExtractor.extract(file.path);
    expect(cover, isNotNull);
    expect(cover!.toList(), image);

    await dir.delete(recursive: true);
  });

  test('returns null when there is no cover', () async {
    final moov = _box('moov', _box('udta', []));
    final dir = await Directory.systemTemp.createTemp('cover_test');
    final file = File('${dir.path}/nocover.m4b');
    await file.writeAsBytes(Uint8List.fromList(moov));

    expect(await CoverExtractor.extract(file.path), isNull);

    await dir.delete(recursive: true);
  });
}
