import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/preventivo_builder_provider.dart';

/// Campo per selezionare PRANZO/CENA, controllato dal Provider.
/// - Legge il valore iniziale da PreventivoBuilderProvider.tipoPasto
/// - Aggiorna il provider quando l’utente cambia
/// - Se [required] è true, espone anche un piccolo messaggio d’errore se non selezionato
class TipoPastoField extends StatelessWidget {
  final bool required;
  const TipoPastoField({super.key, this.required = false});

  @override
  Widget build(BuildContext context) {
    return Consumer<PreventivoBuilderProvider>(
      builder: (_, builder, __) {
        final selected = builder.tipoPasto; // 'pranzo' | 'cena' | null

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tipo pasto', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Pranzo'),
                  selected: selected == 'pranzo',
                  onSelected: (_) => builder.setTipoPasto('pranzo'),
                  selectedColor: const Color.fromARGB(255, 255, 140, 211), // Rosa per il selezionato
                  backgroundColor: Colors.white, // Bianco per non selezionato
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                      color: selected == 'pranzo' ? const Color.fromARGB(255, 255, 140, 211) : Colors.grey.shade400,
                    ),
                  ),
                  labelStyle: TextStyle(
                    color: selected == 'pranzo' ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                ChoiceChip(
                  label: const Text('Cena'),
                  selected: selected == 'cena',
                  onSelected: (_) => builder.setTipoPasto('cena'),
                  selectedColor: const Color.fromARGB(255, 255, 140, 211),
                  backgroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                      color: selected == 'cena' ? const Color.fromARGB(255, 255, 140, 211) : Colors.grey.shade400,
                    ),
                  ),
                  labelStyle: TextStyle(
                    color: selected == 'cena' ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            if (required && selected == null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Seleziona Pranzo o Cena',
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        );

      },
    );
  }
}
