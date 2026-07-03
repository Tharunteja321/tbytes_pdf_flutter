// Copyright (c) 2026 tbytes. Licensed under the MIT License.
// See the LICENSE file in the package root for full license text.

import 'package:flutter/material.dart';

import 'pdf_feature_demo_screen.dart';

void main() {
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'tbytes_pdf_flutter example',
      theme: ThemeData.dark(),
      home: const _PdfUrlPromptScreen(),
    );
  }
}

/// Simple entry screen: paste a URL or local file path to a PDF, then
/// launch the full feature demo against it.
///
/// For best results, use a PDF that has AcroForm fields (ideally including
/// a /Sig field) to see Fields / Fill / Sign in action. Try a separate,
/// password-protected PDF against the Decrypt tab.
class _PdfUrlPromptScreen extends StatefulWidget {
  const _PdfUrlPromptScreen();

  @override
  State<_PdfUrlPromptScreen> createState() => _PdfUrlPromptScreenState();
}

class _PdfUrlPromptScreenState extends State<_PdfUrlPromptScreen> {
  final TextEditingController _controller = TextEditingController(
    text: 'https://www.irs.gov/pub/irs-pdf/fw9.pdf',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1D2E),
        title: const Text('tbytes_pdf_flutter'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text(
              'Enter a PDF URL or local file path to try every feature:',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'PDF URL or path',
                labelStyle: TextStyle(color: Colors.white38),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        PdfFeatureDemoScreen(pdfUrl: _controller.text.trim()),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6C63FF),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text('Open demo'),
            ),
          ],
        ),
      ),
    );
  }
}
