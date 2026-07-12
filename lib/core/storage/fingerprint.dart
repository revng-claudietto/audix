import 'dart:io';
import 'dart:typed_data';

/// A stable identity for an audio file, cheap to compute even for a large book.
///
/// It combines the exact file size with an FNV-1a hash of a chunk from the
/// start and end of the file — enough to tell distinct audiobooks apart while
/// surviving renames and moves (the bytes don't change), without reading
/// hundreds of megabytes or pulling in a crypto dependency.
class FileFingerprint {
  FileFingerprint._();

  static const int _chunk = 256 * 1024; // hash 256 KiB from each end

  /// Computes the fingerprint of [file], or null if it can't be read. Only ever
  /// runs on native platforms; the 32-bit FNV-1a keeps the literals within
  /// JavaScript's safe-integer range so the file still compiles for the web.
  static Future<String?> of(File file) async {
    try {
      final length = await file.length();
      if (length <= 0) return null;
      final raf = await file.open();
      try {
        var hash = 0x811c9dc5; // FNV-1a 32-bit offset basis
        hash = _mix(hash, await _readAt(raf, 0, _chunk, length));
        if (length > _chunk) {
          final tailStart = length - _chunk;
          hash = _mix(hash, await _readAt(raf, tailStart, _chunk, length));
        }
        // Exact size + head/tail hash: unique enough to tell books apart.
        return '$length:${hash.toRadixString(16)}';
      } finally {
        await raf.close();
      }
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List> _readAt(
      RandomAccessFile raf, int start, int len, int fileLen) async {
    await raf.setPosition(start);
    final n = (start + len > fileLen) ? fileLen - start : len;
    return raf.read(n);
  }

  static int _mix(int hash, Uint8List bytes) {
    const int prime = 0x01000193; // FNV-1a 32-bit prime
    for (final b in bytes) {
      hash = ((hash ^ b) * prime) & 0xFFFFFFFF; // stay 32-bit
    }
    return hash;
  }
}
