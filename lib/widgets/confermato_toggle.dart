// lib/widgets/confermato_toggle.dart
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/preventivi_provider.dart';
import '../providers/preventivo_builder_provider.dart';
import '../services/preventivi_service.dart';

/// Widget che:
/// - se NON confermato: mostra un bottone "Firma preventivo" -> apre canvas firma -> conferma su backend
/// - se confermato: mostra solo un badge "CONFERMATO"
class ConfermatoToggle extends StatefulWidget {
  final String preventivoId;
  final bool inizialmenteConfermato;
  final VoidCallback? onConfermato; // opzionale: es. per fare refresh esterno

  const ConfermatoToggle({
    super.key,
    required this.preventivoId,
    required this.inizialmenteConfermato,
    this.onConfermato,
  });

  @override
  State<ConfermatoToggle> createState() => _ConfermatoToggleState();
}

class _ConfermatoToggleState extends State<ConfermatoToggle> {
  late bool _confermato;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _confermato = widget.inizialmenteConfermato;
  }

  @override
  void didUpdateWidget(covariant ConfermatoToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    // se cambia lo stato "iniziale" da fuori, allinea il badge interno
    if (oldWidget.inizialmenteConfermato != widget.inizialmenteConfermato) {
      _confermato = widget.inizialmenteConfermato;
    }
  }

  Future<void> _apriFirmaEConferma() async {
    final risultato = await showDialog<_SignatureResult>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _SignatureDialog(),
    );

    if (!mounted) return;
    if (risultato == null || !risultato.isValid) {
      // firma annullata o vuota
      return;
    }

    // Salvataggio+conferma backend
    setState(() => _saving = true);
    try {
      await PreventiviService().confermaPreventivo(widget.preventivoId);

      // prova a notificare providers, se presenti
      final preventiviProv = context.read<PreventiviProvider?>();
      if (preventiviProv != null) {
        // non blocca la UI; aggiorna la lista in background
        // ignore: unawaited_futures
        preventiviProv.hardRefresh();
      }
      final builder = context.read<PreventivoBuilderProvider?>();
      if (builder != null) {
        // se hai un setter locale dello status usalo (se non esiste, ignora)
        // esempio: builder.setStatus('CONFERMATO');
        try {
          // riflette subito l'UI di questa schermata
          // se il tuo provider espone un setter, scommenta la riga sotto:
          // builder.setStatus('CONFERMATO');
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _confermato = true;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Preventivo confermato e salvato')),
        );
      }

      // callback opzionale (per chi vuole reagire dall’esterno)
      widget.onConfermato?.call();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore durante la conferma: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_confermato) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          const Icon(Icons.verified, color: Colors.green),
          const SizedBox(width: 8),
          Chip(
            label: const Text('CONFERMATO'),
            backgroundColor: Colors.green.withOpacity(0.1),
            side: BorderSide(color: Colors.green.shade600),
            labelStyle: TextStyle(
              color: Colors.green.shade800,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }

    return SizedBox(
      height: 40,
      child: _saving
          ? const Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : ElevatedButton.icon(
              icon: const Icon(Icons.edit_document),
              label: const Text('Firma preventivo'),
              onPressed: _apriFirmaEConferma,
            ),
    );
  }
}

/// Risultato della finestra firma
class _SignatureResult {
  final bool isValid;
  const _SignatureResult(this.isValid);
}

/// Dialog con canvas di firma (no dipendenze esterne)
class _SignatureDialog extends StatefulWidget {
  const _SignatureDialog();

  @override
  State<_SignatureDialog> createState() => _SignatureDialogState();
}

class _SignatureDialogState extends State<_SignatureDialog> {
  final _strokes = <List<Offset>>[];
  List<Offset>? _current;

  bool get _isEmpty {
    // consideriamo "valida" se ci sono almeno un tratto con > 10 punti
    for (final s in _strokes) {
      if (s.length > 10) return false;
    }
    return true;
  }

  void _onPanStart(DragStartDetails d, BoxConstraints c) {
    setState(() {
      _current = [];
      _strokes.add(_current!);
      _current!.add(d.localPosition);
    });
  }

  void _onPanUpdate(DragUpdateDetails d) {
    setState(() {
      _current?.add(d.localPosition);
    });
  }

  void _onPanEnd(DragEndDetails d) {
    setState(() {
      _current = null;
    });
  }

  void _clear() {
    setState(() {
      _strokes.clear();
      _current = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final actionsEnabled = !_isEmpty;

    return AlertDialog(
      title: const Text('Firma preventivo'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: AspectRatio(
          aspectRatio: 4 / 3,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.grey.shade400),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: GestureDetector(
                    onPanStart: (d) => _onPanStart(d, constraints),
                    onPanUpdate: _onPanUpdate,
                    onPanEnd: _onPanEnd,
                    child: CustomPaint(
                      painter: _SignaturePainter(_strokes),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _clear,
          child: const Text('Pulisci'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(const _SignatureResult(false)),
          child: const Text('Annulla'),
        ),
        FilledButton.icon(
          onPressed: actionsEnabled
              ? () => Navigator.of(context).pop(const _SignatureResult(true))
              : null,
          icon: const Icon(Icons.check),
          label: const Text('Conferma firma'),
        ),
      ],
    );
  }
}

class _SignaturePainter extends CustomPainter {
  final List<List<Offset>> strokes;

  _SignaturePainter(this.strokes);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.black
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final s in strokes) {
      if (s.length < 2) continue;
      final path = Path()..moveTo(s.first.dx, s.first.dy);
      for (int i = 1; i < s.length; i++) {
        path.lineTo(s[i].dx, s[i].dy);
      }
      canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) {
    return oldDelegate.strokes != strokes;
  }
}
