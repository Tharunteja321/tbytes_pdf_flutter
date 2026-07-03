// Copyright (c) 2026 tbytes. Licensed under the MIT License.
// See the LICENSE file in the package root for full license text.
//
// This is the example app's main demo screen. It exercises every public
// feature of tbytes_pdf_flutter against a single PDF you provide:
//
//   Tab 1 — Fields    : AcroFormReader — discover and inspect form fields
//   Tab 2 — Fill      : AcroFormReader.setFieldValue — fill text/checkbox/
//                        radio/choice fields
//   Tab 3 — Sign      : SignatureImagePlacer — draw and place a signature
//                        image onto a chosen field
//   Tab 4 — Flatten   : PdfFlattener — bake filled fields/annotations into
//                        static page content
//   Tab 5 — Decrypt   : PdfDecryptor — unlock a password-protected PDF
//   Tab 6 — Result    : view whatever the last operation produced
//
// The PDF viewing itself (CachedPDFViewer) is example-only glue — see
// cached_pdf_view.dart and the root THIRD_PARTY_NOTICES.md. The package
// itself has no viewer dependency.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tbytes_pdf_flutter/tbytes_pdf_flutter.dart';

import 'cached_pdf_view.dart';

class PdfFeatureDemoScreen extends StatefulWidget {
  const PdfFeatureDemoScreen({super.key, required this.pdfUrl});

  /// URL or local path to a PDF. For the best tour of every feature, use a
  /// PDF that has AcroForm fields (ideally including a /Sig field) and,
  /// separately, try a password-protected PDF against the Decrypt tab.
  final String pdfUrl;

  @override
  State<PdfFeatureDemoScreen> createState() => _PdfFeatureDemoScreenState();
}

class _PdfFeatureDemoScreenState extends State<PdfFeatureDemoScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // Shared state
  List<AcroField> _fields = <AcroField>[];
  AcroField? _selectedField;
  bool _loadingFields = false;
  String? _error;
  String? _statusMessage;

  // Sign tab
  final List<List<Offset>> _strokes = <List<Offset>>[];
  List<Offset> _currentStroke = <Offset>[];
  bool _hasSig = false;

  // Fill tab
  final Map<String, TextEditingController> _textControllers =
      <String, TextEditingController>{};
  final Map<String, bool> _checkboxValues = <String, bool>{};

  // Flatten tab
  FlattenQuality _flattenQuality = FlattenQuality.high;
  FlattenTarget _flattenTarget = FlattenTarget.all;
  FlattenResult? _lastFlattenResult;

  // Decrypt tab
  final TextEditingController _passwordController = TextEditingController();
  bool? _isEncrypted;

  // Result
  String? _resultPdfPath;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _loadFields();
    _checkEncryption();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _passwordController.dispose();
    for (final TextEditingController c in _textControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Shared: load current working PDF bytes ─────────────────────────────

  Future<Uint8List> _loadCurrentBytes() async {
    // Use the last result if we've already run an operation this session,
    // otherwise fall back to the original source PDF.
    final String? path =
        _resultPdfPath ?? await PDFCacheManager.instance.getPDFPath(widget.pdfUrl);
    if (path == null) throw Exception('Could not resolve PDF path');
    return File(path).readAsBytes();
  }

  Future<String> _writeResult(List<int> bytes, String label) async {
    final Directory dir = await getApplicationDocumentsDirectory();
    final String outPath =
        '${dir.path}/${label}_${DateTime.now().millisecondsSinceEpoch}.pdf';
    await File(outPath).writeAsBytes(bytes);
    return outPath;
  }

  // ── Tab 1: Fields — AcroFormReader ──────────────────────────────────────

  Future<void> _loadFields() async {
    setState(() {
      _loadingFields = true;
      _error = null;
    });

    try {
      final Uint8List bytes = await _loadCurrentBytes();
      final PdfDoc doc = PdfDoc.load(bytes);
      final AcroFormReader reader = AcroFormReader(doc);

      if (!reader.hasForm) {
        setState(() {
          _error = 'This PDF has no AcroForm fields.\n'
              'Use a PDF that contains form fields to try Fields / Fill / Sign.';
          _loadingFields = false;
          _fields = <AcroField>[];
        });
        return;
      }

      final List<AcroField> fields = reader.readFields();

      setState(() {
        _fields = fields;
        _selectedField = fields.isEmpty
            ? null
            : fields.firstWhere(
                (AcroField f) => f.type == AcroFieldType.signature,
                orElse: () => fields.first,
              );
        _loadingFields = false;
        _statusMessage = 'Found ${fields.length} field(s)';

        // Seed fill controllers
        for (final AcroField f in fields) {
          if (f.type == AcroFieldType.text) {
            _textControllers[f.name] =
                TextEditingController(text: f.textValue ?? '');
          } else if (f.type == AcroFieldType.checkbox) {
            _checkboxValues[f.name] = f.isChecked;
          }
        }
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loadingFields = false;
      });
    }
  }

  // ── Tab 2: Fill — AcroFormReader.setFieldValue ──────────────────────────

  Future<void> _applyFillValues() async {
    setState(() {
      _error = null;
      _statusMessage = 'Filling fields...';
    });

    try {
      final Uint8List bytes = await _loadCurrentBytes();
      final PdfDoc doc = PdfDoc.load(bytes);
      final AcroFormReader reader = AcroFormReader(doc);

      for (final AcroField field in reader.readFields()) {
        if (field.type == AcroFieldType.text &&
            _textControllers.containsKey(field.name)) {
          reader.setFieldValue(field.name, _textControllers[field.name]!.text);
        } else if (field.type == AcroFieldType.checkbox &&
            _checkboxValues.containsKey(field.name)) {
          reader.setFieldValue(field.name, _checkboxValues[field.name]!);
        }
      }

      final PdfWriter writer = PdfWriter();
      final List<int> filledBytes = writer.write(doc);
      final String outPath = await _writeResult(filledBytes, 'filled');

      setState(() {
        _resultPdfPath = outPath;
        _statusMessage = '✅ Fields filled. Open the Result tab to view.';
      });
      _tabController.animateTo(5);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _statusMessage = null;
      });
    }
  }

  // ── Tab 3: Sign — SignatureImagePlacer ──────────────────────────────────

  Future<Uint8List> _renderSignatureToPng() async {
    const double w = 400;
    const double h = 200;

    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w, h));
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()..color = Colors.transparent,
    );

    final Paint paint = Paint()
      ..color = const Color(0xFF1A1A2E)
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (final List<Offset> stroke in _strokes) {
      if (stroke.isEmpty) continue;
      final Path path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (int i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }

    final ui.Picture picture = recorder.endRecording();
    final ui.Image image = await picture.toImage(w.toInt(), h.toInt());
    final ByteData? byteData =
        await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  Future<void> _applySignature() async {
    if (_selectedField == null) return;
    if (!_hasSig) {
      _showSnack('✏️ Please draw your signature first', isError: true);
      return;
    }

    setState(() {
      _error = null;
      _statusMessage = 'Applying signature...';
    });

    try {
      final Uint8List sigPng = await _renderSignatureToPng();

      final Uint8List originalBytes = await _loadCurrentBytes();
      final PdfDoc doc = PdfDoc.load(originalBytes);

      final SignatureImagePlacer placer = SignatureImagePlacer(doc);
      placer.placeSignatureOnField(
        field: _selectedField!,
        imageBytes: sigPng,
        maxWidth: 200.0,
        maxHeight: 60.0,
        offsetX: 10,
        offsetY: 5,
        transparentBackground: true,
      );

      final PdfWriter writer = PdfWriter();
      final List<int> signedBytes = writer.write(doc);
      final String outPath = await _writeResult(signedBytes, 'signed');

      setState(() {
        _resultPdfPath = outPath;
        _statusMessage = '✅ Signature applied. Open the Result tab to view.';
      });
      _tabController.animateTo(5);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _statusMessage = null;
      });
    }
  }

  // ── Tab 4: Flatten — PdfFlattener ───────────────────────────────────────

  Future<void> _applyFlatten() async {
    setState(() {
      _error = null;
      _statusMessage = 'Flattening...';
    });

    try {
      final Uint8List bytes = await _loadCurrentBytes();
      final PdfDoc doc = PdfDoc.load(bytes);

      final PdfFlattener flattener = PdfFlattener(doc);
      final FlattenResult result = flattener.flatten(
        quality: _flattenQuality,
        target: _flattenTarget,
      );

      final PdfWriter writer = PdfWriter();
      final List<int> flatBytes = writer.write(doc);
      final String outPath = await _writeResult(flatBytes, 'flattened');

      setState(() {
        _lastFlattenResult = result;
        _resultPdfPath = outPath;
        _statusMessage = '✅ $result';
      });
      _tabController.animateTo(5);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _statusMessage = null;
      });
    }
  }

  // ── Tab 5: Decrypt — PdfDecryptor ───────────────────────────────────────

  Future<void> _checkEncryption() async {
    try {
      final Uint8List bytes = await _loadCurrentBytes();
      final PdfDoc doc = PdfDoc.load(bytes);
      setState(() => _isEncrypted = PdfDecryptor(doc).isEncrypted);
    } catch (_) {
      // Ignore — the Fields tab will surface load errors.
    }
  }

  Future<void> _applyDecrypt() async {
    setState(() {
      _error = null;
      _statusMessage = 'Decrypting...';
    });

    try {
      final Uint8List bytes = await _loadCurrentBytes();
      final PdfDoc doc = PdfDoc.load(bytes);
      final PdfDecryptor decryptor = PdfDecryptor(doc);

      if (!decryptor.isEncrypted) {
        setState(() {
          _statusMessage = 'This PDF is not encrypted — nothing to do.';
        });
        return;
      }

      final bool ok = decryptor.tryDecrypt(_passwordController.text);
      if (!ok) {
        setState(() {
          _error = 'Incorrect password, or unsupported encryption scheme.';
          _statusMessage = null;
        });
        return;
      }

      final PdfWriter writer = PdfWriter();
      final List<int> decryptedBytes = writer.write(doc);
      final String outPath = await _writeResult(decryptedBytes, 'decrypted');

      setState(() {
        _resultPdfPath = outPath;
        _statusMessage = '✅ Decrypted. Open the Result tab to view.';
      });
      _tabController.animateTo(5);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _statusMessage = null;
      });
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1D2E),
        elevation: 0,
        title: const Text(
          'tbytes_pdf_flutter demo',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: const Color(0xFF6C63FF),
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white38,
          tabs: const <Tab>[
            Tab(icon: Icon(Icons.list_alt_rounded, size: 18), text: 'Fields'),
            Tab(icon: Icon(Icons.edit_note_rounded, size: 18), text: 'Fill'),
            Tab(icon: Icon(Icons.draw_rounded, size: 18), text: 'Sign'),
            Tab(icon: Icon(Icons.layers_clear_rounded, size: 18), text: 'Flatten'),
            Tab(icon: Icon(Icons.lock_open_rounded, size: 18), text: 'Decrypt'),
            Tab(icon: Icon(Icons.preview_rounded, size: 18), text: 'Result'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: <Widget>[
          _buildFieldsTab(),
          _buildFillTab(),
          _buildSignTab(),
          _buildFlattenTab(),
          _buildDecryptTab(),
          _buildResultTab(),
        ],
      ),
    );
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _statusBanner() {
    if (_statusMessage == null && _error == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _error != null
            ? Colors.red.withOpacity(0.1)
            : Colors.green.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _error != null
              ? Colors.red.withOpacity(0.3)
              : Colors.green.withOpacity(0.3),
        ),
      ),
      child: Text(
        _error ?? _statusMessage ?? '',
        style: TextStyle(
          color: _error != null ? Colors.red.shade200 : Colors.green.shade200,
          fontSize: 13,
        ),
      ),
    );
  }

  // ── Tab 1 UI: Fields ─────────────────────────────────────────────────────

  Widget _buildFieldsTab() {
    if (_loadingFields) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF6C63FF)),
      );
    }

    return Column(
      children: <Widget>[
        _statusBanner(),
        if (_fields.isEmpty)
          const Expanded(
            child: Center(
              child: Text('No fields found.',
                  style: TextStyle(color: Colors.white38)),
            ),
          )
        else
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _fields.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (BuildContext context, int i) {
                final AcroField field = _fields[i];
                final bool isSelected = _selectedField?.name == field.name;
                return ListTile(
                  tileColor: isSelected
                      ? const Color(0xFF6C63FF).withOpacity(0.15)
                      : const Color(0xFF1A1D2E),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  title: Text(field.name,
                      style: const TextStyle(color: Colors.white)),
                  subtitle: Text(
                    '${field.type.name} · value: ${field.value}',
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                  onTap: () => setState(() => _selectedField = field),
                );
              },
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton.icon(
            onPressed: _loadFields,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Re-read fields'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6C63FF),
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        ),
      ],
    );
  }

  // ── Tab 2 UI: Fill ───────────────────────────────────────────────────────

  Widget _buildFillTab() {
    final List<AcroField> textFields =
        _fields.where((AcroField f) => f.type == AcroFieldType.text).toList();
    final List<AcroField> checkboxFields = _fields
        .where((AcroField f) => f.type == AcroFieldType.checkbox)
        .toList();

    if (textFields.isEmpty && checkboxFields.isEmpty) {
      return const Center(
        child: Text('No text or checkbox fields to fill.',
            style: TextStyle(color: Colors.white38)),
      );
    }

    return Column(
      children: <Widget>[
        _statusBanner(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              for (final AcroField f in textFields)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextField(
                    controller: _textControllers[f.name],
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: f.name,
                      labelStyle: const TextStyle(color: Colors.white38),
                      enabledBorder: const OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white12)),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
              for (final AcroField f in checkboxFields)
                CheckboxListTile(
                  value: _checkboxValues[f.name] ?? false,
                  onChanged: (bool? v) =>
                      setState(() => _checkboxValues[f.name] = v ?? false),
                  title: Text(f.name,
                      style: const TextStyle(color: Colors.white)),
                  activeColor: const Color(0xFF6C63FF),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton.icon(
            onPressed: _applyFillValues,
            icon: const Icon(Icons.check_rounded),
            label: const Text('Apply fill values'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6C63FF),
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        ),
      ],
    );
  }

  // ── Tab 3 UI: Sign ───────────────────────────────────────────────────────

  Widget _buildSignTab() {
    return Column(
      children: <Widget>[
        _statusBanner(),
        if (_fields.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: DropdownButtonFormField<AcroField>(
              value: _selectedField,
              dropdownColor: const Color(0xFF1A1D2E),
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Field to sign',
                labelStyle: TextStyle(color: Colors.white38),
                border: OutlineInputBorder(),
              ),
              items: _fields
                  .map((AcroField f) => DropdownMenuItem<AcroField>(
                        value: f,
                        child: Text(f.name),
                      ))
                  .toList(),
              onChanged: (AcroField? f) => setState(() => _selectedField = f),
            ),
          ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _SignaturePad(
              strokes: _strokes,
              currentStroke: _currentStroke,
              onStrokeStart: (Offset o) =>
                  setState(() => _currentStroke = <Offset>[o]),
              onStrokeUpdate: (Offset o) =>
                  setState(() => _currentStroke.add(o)),
              onStrokeEnd: () => setState(() {
                if (_currentStroke.isNotEmpty) {
                  _strokes.add(List<Offset>.from(_currentStroke));
                }
                _currentStroke = <Offset>[];
                _hasSig = _strokes.isNotEmpty;
              }),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() {
                    _strokes.clear();
                    _currentStroke = <Offset>[];
                    _hasSig = false;
                  }),
                  child: const Text('Clear'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed:
                      (!_hasSig || _selectedField == null) ? null : _applySignature,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6C63FF),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Apply signature'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Tab 4 UI: Flatten ────────────────────────────────────────────────────

  Widget _buildFlattenTab() {
    return Column(
      children: <Widget>[
        _statusBanner(),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('Quality', style: TextStyle(color: Colors.white70)),
              DropdownButton<FlattenQuality>(
                value: _flattenQuality,
                dropdownColor: const Color(0xFF1A1D2E),
                style: const TextStyle(color: Colors.white),
                items: FlattenQuality.values
                    .map((FlattenQuality q) => DropdownMenuItem<FlattenQuality>(
                          value: q,
                          child: Text(q.name),
                        ))
                    .toList(),
                onChanged: (FlattenQuality? q) =>
                    setState(() => _flattenQuality = q ?? FlattenQuality.high),
              ),
              const SizedBox(height: 16),
              const Text('Target', style: TextStyle(color: Colors.white70)),
              DropdownButton<FlattenTarget>(
                value: _flattenTarget,
                dropdownColor: const Color(0xFF1A1D2E),
                style: const TextStyle(color: Colors.white),
                items: FlattenTarget.values
                    .map((FlattenTarget t) => DropdownMenuItem<FlattenTarget>(
                          value: t,
                          child: Text(t.name),
                        ))
                    .toList(),
                onChanged: (FlattenTarget? t) =>
                    setState(() => _flattenTarget = t ?? FlattenTarget.all),
              ),
            ],
          ),
        ),
        if (_lastFlattenResult != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              _lastFlattenResult.toString(),
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton.icon(
            onPressed: _applyFlatten,
            icon: const Icon(Icons.layers_clear_rounded),
            label: const Text('Flatten PDF'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6C63FF),
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        ),
      ],
    );
  }

  // ── Tab 5 UI: Decrypt ────────────────────────────────────────────────────

  Widget _buildDecryptTab() {
    return Column(
      children: <Widget>[
        _statusBanner(),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                _isEncrypted == null
                    ? 'Checking encryption status...'
                    : _isEncrypted!
                        ? '🔒 This PDF is encrypted.'
                        : '🔓 This PDF is not encrypted.',
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Password (leave blank for none)',
                  labelStyle: TextStyle(color: Colors.white38),
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton.icon(
            onPressed: _applyDecrypt,
            icon: const Icon(Icons.lock_open_rounded),
            label: const Text('Decrypt PDF'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6C63FF),
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        ),
      ],
    );
  }

  // ── Tab 6 UI: Result ─────────────────────────────────────────────────────

  Widget _buildResultTab() {
    if (_resultPdfPath == null) {
      return const Center(
        child: Text(
          'No result yet — run Fill, Sign, Flatten, or Decrypt first.',
          style: TextStyle(color: Colors.white38),
          textAlign: TextAlign.center,
        ),
      );
    }

    return CachedPDFViewer(
      key: ValueKey<String>(_resultPdfPath!),
      pdfUrl: _resultPdfPath!,
      config: const PDFViewerConfig(showPageIndicator: true),
      errorBuilder: (String error) => Center(
        child: Text(error, style: const TextStyle(color: Colors.white54)),
      ),
    );
  }
}

// ─── Signature Drawing Pad ────────────────────────────────────────────────

class _SignaturePad extends StatelessWidget {
  const _SignaturePad({
    required this.strokes,
    required this.currentStroke,
    required this.onStrokeStart,
    required this.onStrokeUpdate,
    required this.onStrokeEnd,
  });

  final List<List<Offset>> strokes;
  final List<Offset> currentStroke;
  final void Function(Offset) onStrokeStart;
  final void Function(Offset) onStrokeUpdate;
  final VoidCallback onStrokeEnd;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF6C63FF).withOpacity(0.4)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: Stack(
          children: <Widget>[
            if (strokes.isEmpty && currentStroke.isEmpty)
              const Center(
                child: Text('Sign here',
                    style: TextStyle(color: Color(0xFFAAAAAA), fontSize: 16)),
              ),
            GestureDetector(
              onPanStart: (DragStartDetails d) => onStrokeStart(d.localPosition),
              onPanUpdate: (DragUpdateDetails d) => onStrokeUpdate(d.localPosition),
              onPanEnd: (_) => onStrokeEnd(),
              child: CustomPaint(
                painter: _SignaturePainter(
                    strokes: strokes, currentStroke: currentStroke),
                child: const SizedBox.expand(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SignaturePainter extends CustomPainter {
  _SignaturePainter({required this.strokes, required this.currentStroke});

  final List<List<Offset>> strokes;
  final List<Offset> currentStroke;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = const Color(0xFF1A1A2E)
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (final List<Offset> stroke in <List<Offset>>[...strokes, currentStroke]) {
      if (stroke.length < 2) continue;
      final Path path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (int i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_SignaturePainter old) => true;
}
