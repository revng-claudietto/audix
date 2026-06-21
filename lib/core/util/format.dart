/// Formats a wall-clock [DateTime] compactly, e.g. `Jun 21, 14:05`
/// (or `2025 Jun 21, 14:05` for a different year).
String formatTimestamp(DateTime dt, {DateTime? now}) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  final year = (now ?? DateTime.now()).year == dt.year ? '' : '${dt.year} ';
  return '$year${months[dt.month - 1]} ${dt.day}, $hh:$mm';
}

/// Formats a [Duration] as `h:mm:ss` (or `m:ss` when under an hour).
String formatDuration(Duration d) {
  final negative = d.isNegative;
  d = d.abs();
  final hours = d.inHours;
  final minutes = d.inMinutes % 60;
  final seconds = d.inSeconds % 60;
  final mm = minutes.toString().padLeft(2, '0');
  final ss = seconds.toString().padLeft(2, '0');
  final text = hours > 0 ? '$hours:$mm:$ss' : '$minutes:$ss';
  return negative ? '-$text' : text;
}
