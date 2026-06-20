import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/storage/file_paths.dart';

/// Shows a book's cover image (resolved synchronously from the cached documents
/// path) with a rounded clip, falling back to a placeholder icon.
class BookCover extends StatelessWidget {
  const BookCover({
    super.key,
    required this.coverPath,
    this.size = 56,
    this.radius = 8,
  });

  /// Db-stored relative cover path, or null.
  final String? coverPath;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final absolute =
        coverPath == null ? null : FilePaths.cachedAbsolute(coverPath!);

    Widget placeholder() => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(radius),
          ),
          child: Icon(
            Icons.menu_book,
            color: scheme.onPrimaryContainer,
            size: size * 0.5,
          ),
        );

    if (absolute == null) return placeholder();
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.file(
        File(absolute),
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => placeholder(),
      ),
    );
  }
}
