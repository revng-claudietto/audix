import 'package:path/path.dart' as p;

/// Resolves where audiobooks live on disk. The root is user-configurable
/// (default `/sdcard/Audiobooks`) and each book sits in a human-named folder
/// under it — `<root>/<Title>/audio.m4b` (+ `index.cue`, `transcript.vtt`).
/// No numeric ids in the path; the library is re-indexed from this tree.
class StorageLocations {
  const StorageLocations(this.root);

  /// Absolute path of the audiobooks directory.
  final String root;

  static const String defaultRoot = '/sdcard/Audiobooks';
  static const String audioName = 'audio.m4b';
  static const String cueName = 'index.cue';
  static const String subtitleName = 'transcript.vtt';

  /// Absolute folder that holds a book titled [title].
  String bookDir(String title) => p.join(root, sanitize(title));

  /// Makes [title] safe as a single folder name (drops path separators and
  /// other characters filesystems dislike, collapses whitespace).
  static String sanitize(String title) {
    final cleaned = title
        .replaceAll(RegExp(r'[/\\:*?"<>|\x00-\x1f]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned.isEmpty ? 'Audiobook' : cleaned;
  }
}
