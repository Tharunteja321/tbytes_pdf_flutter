// Copyright (c) 2026 tbytes. Licensed under the MIT License.
// See the LICENSE file in the package root for full license text.
//
// This file is part of the EXAMPLE APP ONLY. It demonstrates one way to
// view a PDF (using pdfrx + flutter_pdfview) alongside tbytes_pdf_flutter,
// which does not include a viewer itself. See THIRD_PARTY_NOTICES.md at
// the package root for the licenses of pdfrx and flutter_pdfview.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:pdfrx/pdfrx.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Position for page indicator
enum PageIndicatorPosition {
  top,
  bottom,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
}

/// Singleton manager for downloading and caching PDF files
class PDFCacheManager {
  static final PDFCacheManager instance = PDFCacheManager._internal();
  factory PDFCacheManager() => instance;
  PDFCacheManager._internal();

  static const String _lastCacheClearKey = 'pdf_cache_last_clear_time';
  CacheExpirySettings? cacheExpirySettings;
  bool _initialized = false;

  // Helper: resolve app PDF directory
  Future<Directory> _pdfDir() async {
    final Directory directory = await getApplicationDocumentsDirectory();
    final Directory pdfDir = Directory('${directory.path}/cached_pdfs');
    if (!await pdfDir.exists()) {
      await pdfDir.create(recursive: true);
    }
    return pdfDir;
  }

  // Helper: get safe filename from URL (drops query params)
  String _filenameFromUrl(String url) {
    try {
      final Uri uri = Uri.parse(url);
      final String last = uri.pathSegments.isNotEmpty
          ? uri.pathSegments.last
          : '';
      String filename = (last.isEmpty ? url.split('/').last : last)
          .split('?')
          .first;

      // Ensure .pdf extension
      if (!filename.toLowerCase().endsWith('.pdf')) {
        filename = '$filename.pdf';
      }
      return filename;
    } catch (_) {
      String filename = url.split('/').last.split('?').first;
      if (!filename.toLowerCase().endsWith('.pdf')) {
        filename = '$filename.pdf';
      }
      return filename;
    }
  }

  /// Get PDF path (local passthrough or downloaded file)
  Future<String?> getPDFPath(
    String pdfUrl, {
    VoidCallback? fileAlreadyExists,
    Map<String, String>? headers,
    bool checkExpiry = true,
  }) async {
    // Check and clear expired cache before fetching
    if (checkExpiry) {
      await _checkAndClearExpiredCache();
    }

    if (isLocalFile(pdfUrl)) {
      return handleLocalFile(pdfUrl);
    }

    final Directory dir = await _pdfDir();
    final String filename = _filenameFromUrl(pdfUrl);
    final String filePath = '${dir.path}/$filename';

    // Reuse if already downloaded
    final File file = File(filePath);
    if (await file.exists()) {
      fileAlreadyExists?.call();
      return filePath;
    }

    // Not found locally → download to deterministic path
    return await _downloadPDF(pdfUrl, targetPath: filePath, headers: headers);
  }

  /// Check if the URL points to a local file
  bool isLocalFile(String url) {
    return url.startsWith('file://') ||
        url.startsWith('/') ||
        (url.contains('://') == false && File(url).existsSync());
  }

  /// Handle local file path
  String? handleLocalFile(String localPath) {
    try {
      final String cleanPath = localPath.startsWith('file://')
          ? localPath.substring(7)
          : localPath;
      final File file = File(cleanPath);
      return file.existsSync() ? cleanPath : null;
    } catch (e) {
      debugPrint('Error handling local file: $e');
      return null;
    }
  }

  /// Download PDF from network
  Future<String?> _downloadPDF(
    String pdfUrl, {
    required String targetPath,
    Map<String, String>? headers,
  }) async {
    try {
      debugPrint('📥 PDF Download started');
      debugPrint('➡️ URL: $pdfUrl');
      debugPrint('📁 Target path: $targetPath');

      final Uri uri = Uri.parse(pdfUrl);
      debugPrint('🌐 Making HTTP GET request...');

      final http.Response response = await http.get(uri, headers: headers);

      debugPrint('📡 Response received');
      debugPrint('🔢 Status code: ${response.statusCode}');
      debugPrint('📦 Response size: ${response.bodyBytes.length} bytes');

      if (response.statusCode == 200) {
        debugPrint('✅ Status OK (200), writing file...');

        final File file = File(targetPath);
        await file.writeAsBytes(response.bodyBytes);

        debugPrint('💾 File written successfully');
        debugPrint('✔️ Download completed');

        return targetPath;
      } else {
        debugPrint('❌ Download failed with status: ${response.statusCode}');
        return null;
      }
    } catch (e, stackTrace) {
      debugPrint('🔥 Error downloading PDF');
      debugPrint('🧨 Exception: $e');
      debugPrint('📚 StackTrace: $stackTrace');
      return null;
    }
  }

  /// Get local path if file exists (without downloading)
  Future<String?> getLocalPath(String pdfUrl) async {
    if (isLocalFile(pdfUrl)) return handleLocalFile(pdfUrl);
    final Directory dir = await _pdfDir();
    final String path = '${dir.path}/${_filenameFromUrl(pdfUrl)}';
    return await File(path).exists() ? path : null;
  }

  /// Check if PDF is available locally
  Future<bool> isPDFAvailable(String pdfUrl) async {
    if (isLocalFile(pdfUrl)) return handleLocalFile(pdfUrl) != null;
    final Directory dir = await _pdfDir();
    final String path = '${dir.path}/${_filenameFromUrl(pdfUrl)}';
    return await File(path).exists();
  }

  /// Delete a cached PDF file
  Future<bool> deletePDF(String pdfUrl) async {
    try {
      final String? localPath = await getLocalPath(pdfUrl);
      if (localPath != null) {
        final File file = File(localPath);
        if (await file.exists()) {
          await file.delete();
          debugPrint('🗑️ Deleted PDF: $localPath');
          return true;
        }
      }
      return false;
    } catch (e) {
      debugPrint('Error deleting PDF: $e');
      return false;
    }
  }

  /// Clear all cached PDFs
  Future<bool> clearCache({
    bool updateTimestamp = true,
    List<String> excludePatterns = const <String>[],
  }) async {
    try {
      final Directory dir = await _pdfDir();

      if (await dir.exists()) {
        if (excludePatterns.isEmpty) {
          // No exclusions — delete everything as before
          await dir.delete(recursive: true);
          await dir.create(recursive: true);
        } else {
          // ✅ Delete files one by one, skipping excluded patterns
          await for (final FileSystemEntity entity in dir.list()) {
            if (entity is File) {
              final String filename = entity.path.split('/').last;
              final bool shouldExclude = excludePatterns.any(
                (String pattern) => filename.contains(pattern),
              );
              if (shouldExclude) {
                debugPrint('⏭️ Skipping excluded file: $filename');
              } else {
                await entity.delete();
                debugPrint('🗑️ Deleted: $filename');
              }
            }
          }
        }
      }

      if (updateTimestamp) {
        await _updateLastClearTime();
      }

      debugPrint('🗑️ Cleared cached PDFs');
      return true;
    } catch (e) {
      debugPrint('Error clearing PDF cache: $e');
      return false;
    }
  }

  /// Get total cache size in bytes
  Future<int> getCacheSize() async {
    try {
      final Directory dir = await _pdfDir();
      if (!await dir.exists()) return 0;

      int totalSize = 0;
      await for (final FileSystemEntity entity in dir.list(recursive: true)) {
        if (entity is File) {
          totalSize += await entity.length();
        }
      }
      return totalSize;
    } catch (e) {
      debugPrint('Error calculating cache size: $e');
      return 0;
    }
  }

  /// Initialize cache manager and check for expiry
  /// Call this in main() or app initialization
  Future<void> initialize({CacheExpirySettings? expirySettings}) async {
    if (_initialized) return;

    cacheExpirySettings = expirySettings;

    if (cacheExpirySettings?.clearOnAppStart == true) {
      await _checkAndClearExpiredCache();
    }

    _initialized = true;
    debugPrint('📁 PDFCacheManager initialized');
  }

  /// Check if cache has expired and clear if needed
  Future<bool> _checkAndClearExpiredCache() async {
    if (cacheExpirySettings?.maxAge == null) {
      return false;
    }

    final bool isExpired = await isCacheExpired();
    if (isExpired) {
      debugPrint('🗑️ Cache expired, clearing...');
      await clearCache();
      await _updateLastClearTime();
      return true;
    }

    return false;
  }

  /// Check if cache has expired based on maxAge setting
  Future<bool> isCacheExpired() async {
    if (cacheExpirySettings?.maxAge == null) {
      return false;
    }

    final DateTime? lastClearTime = await _getLastClearTime();
    if (lastClearTime == null) {
      // First time, set the clear time and don't clear
      await _updateLastClearTime();
      return false;
    }

    final DateTime now = DateTime.now();
    final Duration elapsed = now.difference(lastClearTime);

    return elapsed >= cacheExpirySettings!.maxAge!;
  }

  /// Get time until next cache clear
  Future<Duration?> getTimeUntilNextClear() async {
    if (cacheExpirySettings?.maxAge == null) {
      return null;
    }

    final DateTime? lastClearTime = await _getLastClearTime();
    if (lastClearTime == null) {
      return cacheExpirySettings!.maxAge;
    }

    final DateTime nextClearTime = lastClearTime.add(
      cacheExpirySettings!.maxAge!,
    );
    final DateTime now = DateTime.now();

    if (now.isAfter(nextClearTime)) {
      return Duration.zero;
    }

    return nextClearTime.difference(now);
  }

  /// Get last cache clear time from SharedPreferences
  Future<DateTime?> _getLastClearTime() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final int? timestamp = prefs.getInt(_lastCacheClearKey);
      if (timestamp == null) return null;
      return DateTime.fromMillisecondsSinceEpoch(timestamp);
    } catch (e) {
      debugPrint('Error getting last clear time: $e');
      return null;
    }
  }

  /// Update last cache clear time in SharedPreferences
  Future<void> _updateLastClearTime() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        _lastCacheClearKey,
        DateTime.now().millisecondsSinceEpoch,
      );
      debugPrint('✅ Cache clear time updated');
    } catch (e) {
      debugPrint('Error updating last clear time: $e');
    }
  }

  /// Get last cache clear time (public)
  Future<DateTime?> getLastClearTime() => _getLastClearTime();

  /// Force clear cache and update timestamp
  Future<bool> forceClearCache() async {
    final bool result = await clearCache();
    if (result) {
      await _updateLastClearTime();
    }
    return result;
  }

  /// Get cache info including expiry details
  Future<CacheInfo> getCacheInfo() async {
    final int size = await getCacheSize();
    final DateTime? lastClear = await _getLastClearTime();
    final Duration? timeUntilClear = await getTimeUntilNextClear();
    final bool isExpired = await isCacheExpired();
    final int fileCount = await _getCacheFileCount();

    return CacheInfo(
      sizeInBytes: size,
      fileCount: fileCount,
      lastClearTime: lastClear,
      timeUntilNextClear: timeUntilClear,
      isExpired: isExpired,
      maxAge: cacheExpirySettings?.maxAge,
    );
  }

  /// Get number of cached files
  Future<int> _getCacheFileCount() async {
    try {
      final Directory dir = await _pdfDir();
      if (!await dir.exists()) return 0;

      int count = 0;
      await for (final FileSystemEntity entity in dir.list()) {
        if (entity is File) {
          count++;
        }
      }
      return count;
    } catch (e) {
      return 0;
    }
  }
}

/// Configuration for PDF viewer
class PDFViewerConfig {
  const PDFViewerConfig({
    this.defaultPage = 0,
    this.onRender,
    this.onPageChanged,
    this.showPageIndicator = true,
    this.pageIndicatorPosition = PageIndicatorPosition.bottom,
    // iOS (flutter_pdfview) specific — ignored on Android
    this.enableSwipe = true,
    this.swipeHorizontal = false,
    this.password,
    this.nightMode = false,
    this.fitPolicy = FitPolicy.WIDTH,
  });

  final int defaultPage;
  final void Function(int? pages)? onRender;
  final void Function(int? page, int? total)? onPageChanged;
  final bool showPageIndicator;
  final PageIndicatorPosition pageIndicatorPosition;
  final bool enableSwipe;
  final bool swipeHorizontal;
  final String? password;
  final bool nightMode;
  final FitPolicy fitPolicy;
}

/// Widget for displaying cached PDF with download progress and page indicator
class CachedPDFViewer extends StatefulWidget {
  const CachedPDFViewer({
    super.key,
    required this.pdfUrl,
    this.config = const PDFViewerConfig(),
    this.headers,
    this.placeholderBuilder,
    this.errorBuilder,
    this.onDownloadComplete,
    this.pageIndicatorBuilder,
  });

  /// PDF URL
  final String pdfUrl;

  /// PDF viewer configuration
  final PDFViewerConfig config;

  /// HTTP headers for downloading
  final Map<String, String>? headers;

  /// Widget displayed while downloading (receives progress 0-100)
  final Widget Function(double progress)? placeholderBuilder;

  /// Widget displayed on error
  final Widget Function(String error)? errorBuilder;

  /// Callback when download completes
  final void Function(String filePath)? onDownloadComplete;

  /// Custom page indicator builder
  final Widget Function(int currentPage, int totalPages)? pageIndicatorBuilder;

  @override
  State<CachedPDFViewer> createState() => _CachedPDFViewerState();
}

class _CachedPDFViewerState extends State<CachedPDFViewer> {
  int _currentPage = 0;
  int _totalPages = 0;
  String? _filePath;
  String? _error;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPDF();
  }

  Future<void> _loadPDF() async {
    try {
      final String? path = await PDFCacheManager.instance.getPDFPath(
        widget.pdfUrl,
        headers: widget.headers,
        fileAlreadyExists: () {
          debugPrint('PDF already cached: ${widget.pdfUrl}');
        },
      );

      if (mounted) {
        setState(() {
          _filePath = path;
          _isLoading = false;
        });

        if (path != null && widget.onDownloadComplete != null) {
          widget.onDownloadComplete!(path);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return widget.errorBuilder?.call(_error!) ??
          Center(child: Text('Error: $_error'));
    }

    if (_filePath == null) {
      return widget.errorBuilder?.call('Failed to load PDF') ??
          const Center(child: Text('Failed to load PDF'));
    }

    return Stack(
      children: <Widget>[
        Platform.isIOS ? _buildIOSViewer() : _buildAndroidViewer(),
        if (widget.config.showPageIndicator && _totalPages > 0)
          _buildPageIndicator(),
      ],
    );
  }

  // iOS — flutter_pdfview uses native PDFKit, safe for TestFlight/App Store
  Widget _buildIOSViewer() {
    return PDFView(
      filePath: _filePath,
      enableSwipe: widget.config.enableSwipe,
      swipeHorizontal: widget.config.swipeHorizontal,
      password: widget.config.password,
      nightMode: widget.config.nightMode,
      autoSpacing: true,
      pageFling: true,
      pageSnap: true,
      defaultPage: widget.config.defaultPage,
      fitPolicy: widget.config.fitPolicy,
      preventLinkNavigation: false,
      onRender: (int? pages) {
        setState(() {
          _totalPages = pages ?? 0;
          _currentPage = widget.config.defaultPage;
        });
        widget.config.onRender?.call(pages);
      },
      onPageChanged: (int? page, int? total) {
        setState(() {
          _currentPage = page ?? 0;
          _totalPages = total ?? 0;
        });
        widget.config.onPageChanged?.call(page, total);
      },
      onError: (dynamic error) => debugPrint('PDFView error: $error'),
    );
  }

  // Android — pdfrx uses PDFium, correctly renders AcroForm + flattened signatures
  Widget _buildAndroidViewer() {
    return PdfViewer.file(
      _filePath!,
      initialPageNumber: widget.config.defaultPage + 1,
      params: PdfViewerParams(
        annotationRenderingMode: PdfAnnotationRenderingMode.annotationAndForms,
        onPageChanged: (int? page) {
          if (page == null) return;
          setState(() => _currentPage = page - 1);
          widget.config.onPageChanged?.call(page - 1, _totalPages);
        },
        onViewerReady:
            (PdfDocument document, PdfViewerController controller) async {
              setState(() => _totalPages = controller.pageCount);
              widget.config.onRender?.call(controller.pageCount);
            },
      ),
    );
  }

  Widget _buildPageIndicator() {
    // Use custom builder if provided
    if (widget.pageIndicatorBuilder != null) {
      return _positionedIndicator(
        widget.pageIndicatorBuilder!(_currentPage, _totalPages),
      );
    }

    // Default page indicator
    return _positionedIndicator(
      PDFPageIndicator(
        currentPage: _currentPage + 1, // Convert to 1-based index
        totalPages: _totalPages,
        onPageTap: null,
        backgroundColor: Colors.white,
        textColor: Colors.black,
      ),
    );
  }

  Widget _positionedIndicator(Widget child) {
    switch (widget.config.pageIndicatorPosition) {
      case PageIndicatorPosition.top:
        return Positioned(
          top: 16,
          left: 0,
          right: 0,
          child: Center(child: child),
        );
      case PageIndicatorPosition.bottom:
        return Positioned(
          bottom: 16,
          left: 0,
          right: 0,
          child: Center(child: child),
        );
      case PageIndicatorPosition.topLeft:
        return Positioned(top: 16, left: 16, child: child);
      case PageIndicatorPosition.topRight:
        return Positioned(top: 16, right: 16, child: child);
      case PageIndicatorPosition.bottomLeft:
        return Positioned(bottom: 16, left: 16, child: child);
      case PageIndicatorPosition.bottomRight:
        return Positioned(bottom: 16, right: 16, child: child);
    }
  }
}

/// Default page indicator widget
class PDFPageIndicator extends StatelessWidget {
  const PDFPageIndicator({
    super.key,
    required this.currentPage,
    required this.totalPages,
    this.onPageTap,
    this.backgroundColor,
    this.textColor,
    this.borderRadius = 20,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  });

  final int currentPage;
  final int totalPages;
  final VoidCallback? onPageTap;
  final Color? backgroundColor;
  final Color? textColor;
  final double borderRadius;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPageTap,
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: backgroundColor ?? Colors.black,
          borderRadius: BorderRadius.circular(borderRadius),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              '$currentPage / $totalPages',
              style: TextStyle(
                color: textColor ?? Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (onPageTap != null) ...<Widget>[
              const SizedBox(width: 8),
              Icon(
                Icons.keyboard_arrow_down,
                color: textColor ?? Colors.white,
                size: 18,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Widget wrapper for PDFView
class PDFViewerWidget extends StatelessWidget {
  const PDFViewerWidget({
    super.key,
    required this.filePath,
    required this.config,
  });

  final String filePath;
  final PDFViewerConfig config;

  @override
  Widget build(BuildContext context) {
    if (Platform.isIOS) {
      return PDFView(
        filePath: filePath,
        enableSwipe: config.enableSwipe,
        swipeHorizontal: config.swipeHorizontal,
        password: config.password,
        nightMode: config.nightMode,
        defaultPage: config.defaultPage,
        fitPolicy: config.fitPolicy,
      );
    }
    return PdfViewer.file(
      filePath,
      initialPageNumber: config.defaultPage + 1,
      params: const PdfViewerParams(
        annotationRenderingMode: PdfAnnotationRenderingMode.annotationAndForms,
      ),
    );
  }
}

/// Stream-based cached PDF viewer with progress tracking
class StreamedCachedPDFViewer extends StatefulWidget {
  const StreamedCachedPDFViewer({
    super.key,
    required this.pdfUrl,
    this.config = const PDFViewerConfig(),
    this.headers,
    this.placeholderBuilder,
    this.errorBuilder,
    this.onDownloadComplete,
  });

  final String pdfUrl;
  final PDFViewerConfig config;
  final Map<String, String>? headers;
  final Widget Function(double progress)? placeholderBuilder;
  final Widget Function(String error)? errorBuilder;
  final void Function(String filePath)? onDownloadComplete;

  @override
  State<StreamedCachedPDFViewer> createState() =>
      _StreamedCachedPDFViewerState();
}

class _StreamedCachedPDFViewerState extends State<StreamedCachedPDFViewer> {
  double _downloadProgress = 0.0;
  String? _filePath;
  String? _error;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPDF();
  }

  Future<void> _loadPDF() async {
    try {
      final String? path = await PDFCacheManager.instance.getPDFPath(
        widget.pdfUrl,
        headers: widget.headers,
        fileAlreadyExists: () {
          if (mounted) {
            setState(() {
              _downloadProgress = 100.0;
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _filePath = path;
          _isLoading = false;
          _downloadProgress = 100.0;
        });

        if (path != null && widget.onDownloadComplete != null) {
          widget.onDownloadComplete!(path);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return widget.placeholderBuilder?.call(_downloadProgress) ??
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text('${_downloadProgress.toStringAsFixed(0)}%'),
              ],
            ),
          );
    }

    if (_error != null) {
      return widget.errorBuilder?.call(_error!) ??
          Center(child: Text('Error: $_error'));
    }

    if (_filePath == null) {
      return widget.errorBuilder?.call('Failed to load PDF') ??
          const Center(child: Text('Failed to load PDF'));
    }

    return PDFViewerWidget(filePath: _filePath!, config: widget.config);
  }
}

/// Cache expiry settings
class CacheExpirySettings {
  const CacheExpirySettings({this.maxAge, this.clearOnAppStart = false});

  /// Maximum age of cache before auto-clearing
  /// Set to null to disable auto-clearing
  final Duration? maxAge;

  /// Clear cache when app starts (if expired)
  final bool clearOnAppStart;

  // Convenience constructors
  static CacheExpirySettings hours(int hours) =>
      CacheExpirySettings(maxAge: Duration(hours: hours));

  static CacheExpirySettings days(int days) =>
      CacheExpirySettings(maxAge: Duration(days: days));

  static CacheExpirySettings minutes(int minutes) =>
      CacheExpirySettings(maxAge: Duration(minutes: minutes));

  static const CacheExpirySettings oneDay = CacheExpirySettings(
    maxAge: Duration(days: 1),
  );

  static const CacheExpirySettings oneWeek = CacheExpirySettings(
    maxAge: Duration(days: 7),
  );

  static const CacheExpirySettings oneMonth = CacheExpirySettings(
    maxAge: Duration(days: 30),
  );
}

/// Cache information model
class CacheInfo {
  const CacheInfo({
    required this.sizeInBytes,
    required this.fileCount,
    this.lastClearTime,
    this.timeUntilNextClear,
    this.isExpired = false,
    this.maxAge,
  });

  final int sizeInBytes;
  final int fileCount;
  final DateTime? lastClearTime;
  final Duration? timeUntilNextClear;
  final bool isExpired;
  final Duration? maxAge;

  String get formattedSize {
    if (sizeInBytes < 1024) return '$sizeInBytes B';
    if (sizeInBytes < 1024 * 1024) {
      return '${(sizeInBytes / 1024).toStringAsFixed(2)} KB';
    }
    return '${(sizeInBytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  String get formattedTimeUntilClear {
    if (timeUntilNextClear == null) return 'Never';
    if (timeUntilNextClear == Duration.zero) return 'Expired';

    final int hours = timeUntilNextClear!.inHours;
    final int minutes = timeUntilNextClear!.inMinutes % 60;

    if (hours > 24) {
      final int days = hours ~/ 24;
      return '$days day${days > 1 ? 's' : ''}';
    } else if (hours > 0) {
      return '$hours hr $minutes min';
    } else {
      return '$minutes min';
    }
  }

  String get formattedLastClear {
    if (lastClearTime == null) return 'Never';

    final Duration ago = DateTime.now().difference(lastClearTime!);

    if (ago.inDays > 0) {
      return '${ago.inDays} day${ago.inDays > 1 ? 's' : ''} ago';
    } else if (ago.inHours > 0) {
      return '${ago.inHours} hour${ago.inHours > 1 ? 's' : ''} ago';
    } else if (ago.inMinutes > 0) {
      return '${ago.inMinutes} minute${ago.inMinutes > 1 ? 's' : ''} ago';
    } else {
      return 'Just now';
    }
  }
}
