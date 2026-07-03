// Copyright (c) 2026 tbytes. Licensed under the MIT License.
// See the LICENSE file in the package root for full license text.

/// A minimal internal debug logger used throughout this package.
///
/// This exists so the package has no dependency on any host application's
/// own logging utilities. It only prints in debug builds (guarded by
/// [kDebugMode]), so it has no output — and negligible cost — in release
/// builds.
///
/// This class is not exported from the package's public API — it is an
/// internal implementation detail used by the PDF parsing, writing,
/// flattening, decryption, and signature-placement code to trace what's
/// happening without requiring consumers to configure anything.
library;

import 'dart:developer' as developer;

import 'package:flutter/foundation.dart' show kDebugMode;

enum LogLevel { success, warning, error, custom }

class Logger {
  Logger._();

  static const Map<LogLevel, String> _logIcons = <LogLevel, String>{
    LogLevel.success: '🟢',
    LogLevel.warning: '🟠',
    LogLevel.error: '🔴',
    LogLevel.custom: '🟣',
  };

  // ANSI color codes (visible in terminals; harmless elsewhere).
  static const String _red = '\u001b[31m';
  static const String _yellow = '\u001b[33m';
  static const String _green = '\u001b[32m';
  static const String _reset = '\u001b[0m';
  static const String _purple = '\u001b[35m';

  static const Map<LogLevel, String> _logColors = <LogLevel, String>{
    LogLevel.success: _green,
    LogLevel.warning: _yellow,
    LogLevel.error: _red,
    LogLevel.custom: _purple,
  };

  static void _log(
    LogLevel level,
    String? message, {
    DateTime? time,
    String name = 'tbytes_pdf_flutter',
    StackTrace? stackTrace,
  }) {
    if (kDebugMode) {
      final String icon = _logIcons[level] ?? '⚪';
      final String color = _logColors[level] ?? _reset;
      final String formattedMessage = '$icon $color$message$_reset';
      developer.log(
        formattedMessage,
        time: time,
        name: name,
        stackTrace: stackTrace,
      );
    }
  }

  /// General-purpose debug trace, used throughout the package's parsing,
  /// writing, flattening, decryption, and signature-placement code.
  static void debug(String message) => _log(LogLevel.custom, message);

  /// Reports a successful operation.
  static void success(String message) => _log(LogLevel.success, message);

  /// Reports a recoverable issue or unexpected-but-handled condition.
  static void warning(String message) => _log(LogLevel.warning, message);

  /// Reports an error, optionally with a stack trace.
  static void error(String message, {StackTrace? stackTrace}) =>
      _log(LogLevel.error, message, stackTrace: stackTrace);
}
