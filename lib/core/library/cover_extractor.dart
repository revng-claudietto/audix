import 'dart:io';
import 'dart:typed_data';

/// Extracts embedded cover artwork from an MP4 / M4A / M4B file by reading the
/// `moov.udta.meta.ilst.covr.data` atom. Returns the raw image bytes (JPEG or
/// PNG) or null if there is no embedded cover. Pure Dart, no dependencies.
class CoverExtractor {
  static Future<Uint8List?> extract(String filePath) async {
    RandomAccessFile? raf;
    try {
      raf = await File(filePath).open();
      final length = await raf.length();
      final moov = await _readTopLevelBox(raf, length, 'moov');
      if (moov == null) return null;
      return _findCover(moov);
    } catch (_) {
      return null;
    } finally {
      await raf?.close();
    }
  }

  /// Scans top-level boxes (handling boxes located anywhere in the file) and
  /// returns the payload bytes of the first one named [type].
  static Future<Uint8List?> _readTopLevelBox(
      RandomAccessFile raf, int fileLength, String type) async {
    var offset = 0;
    while (offset + 8 <= fileLength) {
      await raf.setPosition(offset);
      final header = await raf.read(8);
      if (header.length < 8) break;
      var size = _u32(header, 0);
      final boxType = String.fromCharCodes(header, 4, 8);
      var headerLen = 8;
      if (size == 1) {
        final ext = await raf.read(8);
        if (ext.length < 8) break;
        size = _u64(ext, 0);
        headerLen = 16;
      } else if (size == 0) {
        size = fileLength - offset; // extends to end of file
      }
      if (size < headerLen) break;
      if (boxType == type) {
        await raf.setPosition(offset + headerLen);
        return Uint8List.fromList(await raf.read(size - headerLen));
      }
      offset += size;
    }
    return null;
  }

  static Uint8List? _findCover(Uint8List moov) {
    final udta = _childBox(moov, 0, moov.length, 'udta');
    if (udta == null) return null;
    final meta = _childBox(moov, udta.$1, udta.$2, 'meta');
    if (meta == null) return null;
    // `meta` is a full box: skip its 4-byte version/flags before its children.
    final ilst = _childBox(moov, meta.$1 + 4, meta.$2, 'ilst');
    if (ilst == null) return null;
    final covr = _childBox(moov, ilst.$1, ilst.$2, 'covr');
    if (covr == null) return null;
    final data = _childBox(moov, covr.$1, covr.$2, 'data');
    if (data == null) return null;
    // `data` atom: 4-byte type indicator + 4-byte locale, then the image bytes.
    final imageStart = data.$1 + 8;
    if (imageStart >= data.$2) return null;
    return Uint8List.sublistView(moov, imageStart, data.$2);
  }

  /// Returns (payloadStart, payloadEnd) of the first child box named [type]
  /// within `[start, end)`, or null.
  static (int, int)? _childBox(Uint8List data, int start, int end, String type) {
    var offset = start;
    while (offset + 8 <= end) {
      var size = _u32(data, offset);
      final boxType = String.fromCharCodes(data, offset + 4, offset + 8);
      var headerLen = 8;
      if (size == 1) {
        if (offset + 16 > end) break;
        size = _u64(data, offset + 8);
        headerLen = 16;
      } else if (size == 0) {
        size = end - offset;
      }
      if (size < headerLen || offset + size > end) break;
      if (boxType == type) return (offset + headerLen, offset + size);
      offset += size;
    }
    return null;
  }

  static int _u32(List<int> b, int o) =>
      (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];

  static int _u64(List<int> b, int o) {
    var v = 0;
    for (var i = 0; i < 8; i++) {
      v = (v << 8) | b[o + i];
    }
    return v;
  }
}
