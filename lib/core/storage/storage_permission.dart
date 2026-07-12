import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Thrown when an operation needs all-files access that the user hasn't granted.
class StoragePermissionException implements Exception {
  const StoragePermissionException();

  @override
  String toString() =>
      'Storage permission needed — grant "All files access" in Settings';
}

/// Wraps Android's "All files access" (MANAGE_EXTERNAL_STORAGE), required to
/// read/write a shared path like `/sdcard/Audiobooks` on Android 11+. It's
/// backed by a small MethodChannel in MainActivity (no plugin dependency).
/// Treated as always-granted on non-Android platforms (nothing to gate).
class StoragePermission {
  StoragePermission._();

  static const MethodChannel _channel = MethodChannel('audix/storage');

  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Whether the app currently has all-files access.
  static Future<bool> isGranted() async {
    if (!_isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>('hasAllFilesAccess') ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Sends the user to the system settings screen to grant all-files access.
  static Future<void> request() async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod<void>('requestAllFilesAccess');
    } on PlatformException {
      // Nothing else we can do from here; the caller re-checks isGranted().
    }
  }
}
