// lib/widgets/firma_dialog.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:signature/signature.dart';


class FirmaDialog extends StatefulWidget {
  const FirmaDialog({
    super.key,
    this.title = 'Firma',
    this.subtitle,
    this.penColor = Colors.black,
    this.backgroundColor = Colors.white,
    this.strokeWidth = 3.0,
  });

  final String title;            // es. "Firma Cliente" o "Firma Pepe Rosa"
  final String? subtitle;        // opzionale (es. “Nettuno 07/10/2025”)
  final Color penColor;
  final Color backgroundColor;
  final double strokeWidth;

  @override
  State<FirmaDialog> createState() => _FirmaDialogState();
}

class _FirmaDialogState extends State<FirmaDialog> {
  late final SignatureController _controller;

  @override
  void initState() {
    super.initState();
    _controller = SignatureController(
      penStrokeWidth: widget.strokeWidth,
      penColor: widget.penColor,
      exportBackgroundColor: widget.backgroundColor, // PNG con sfondo bianco
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _conferma() async {
    if (_controller.isEmpty) {
      Navigator.of(context).pop<Uint8List?>(null);
      return;
    }
    final bytes = await _controller.toPngBytes();
    Navigator.of(context).pop<Uint8List?>(bytes == null || bytes.isEmpty ? null : bytes);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    // Dialog “responsive” con limiti
    final dialogWidth = size.width.clamp(420.0, 780.0);
    final canvasHeight = (dialogWidth * 0.6).clamp(220.0, 460.0);

    return AlertDialog(
      title: Text(widget.title),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      content: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: dialogWidth.toDouble()),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.subtitle != null) ...[
              Text(widget.subtitle!, textAlign: TextAlign.center),
              const SizedBox(height: 8),
            ],
            // Canvas firma con bordo e sfondo
            SizedBox(
              width: dialogWidth.toDouble(),
              height: canvasHeight.toDouble(),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade400),
                  color: widget.backgroundColor,
                ),
                child: Signature(
                  controller: _controller,
                  backgroundColor: widget.backgroundColor,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Firma all’interno del riquadro. Puoi cancellare e rifare.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop<Uint8List?>(null),
          child: const Text('Annulla'),
        ),
        TextButton(
          onPressed: () => _controller.clear(),
          child: const Text('Pulisci'),
        ),
        ElevatedButton(
          onPressed: _conferma,
          child: const Text('Conferma'),
        ),
      ],
    );
  }
}
